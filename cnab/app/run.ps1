#!/usr/bin/env pwsh
# Strict Mode

#Requires -Version 7.4
Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Trap to ensure errors get shown as errors in Octopus Deploy, otherwise they'd go to Verbose because the
# 00-cnab-base.sh script sets '##octopus[stderr-progress]' to avoid all stderr showing up as errors.
# We'll assume we're running under Octopus Deploy if the error happens before we've determined $IsOctopusDeploy.
trap {
  if (!(Test-Path Variable:\IsOctopusDeploy) -or $IsOctopusDeploy) {
    Write-Host '##octopus[stderr-default]'
  }
  break
}

. $PSScriptRoot/app.ps1
. $PSScriptRoot/utils.ps1
. $PSScriptRoot/container-registry-discovery.ps1

if (-not $env:INSTALLATION_METADATA) {
  throw "INSTALLATION_METADATA is not set"
}

# Get installation metadata before we do anything else because some
# apps might need $vars to be set when calling Get-AppName
Write-Verbose "INSTALLATION_METADATA is set to '$env:INSTALLATION_METADATA'"
$vars = (Get-Content $env:INSTALLATION_METADATA | ConvertFrom-Json) 
Initialize-Logging

$environment = $vars.pipeline.env
$project = $vars.pipeline.name

$app = Get-AppName
Write-Output "$($PSStyle.Bold)Installing $app...$($PSStyle.BoldOff)"


Write-Output "Tool versions:"
Invoke-WithEcho gcloud version 
Invoke-WithEcho kubectl version --client=true
Invoke-WithEcho helm version --short
Invoke-WithEcho helm plugin list
Invoke-WithEcho helm diff version

$action = $env:CNAB_ACTION

Write-MajorStep "Running $action for Environment: $environment - Project: $project in cloud: $($vars.pipeline.cloud)"

$deploymentTarget = $vars.deployment_targets[0]  

Write-MajorStep "Connecting to deployment target $($deploymentTarget.id)"
Invoke-Expression $deploymentTarget.vars.k8s_cmd[0]

$releaseTag = $env:BUNDLE_VERSION
# If the release tag starts with a commit hash plus dash "-", strip the extra characters. This lets us easily test Octopus pr's
$releaseTag = $releaseTag -replace '([a-z0-9]{40})-.*', '$1'

$singleRegistry = Is-SingleRegistry
$containerRegistryDetails = Find-ContainerRegistry $releaseTag $singleRegistry
$containerRegistryUrl = $containerRegistryDetails.Url
$pullSecretName = $containerRegistryDetails.PullSecretName
$forceUpgrade = $containerRegistryDetails.ForceUpgrade

Write-Output "Container registry: $containerRegistryUrl"
Write-Output "Pull secret name: $pullSecretName"

switch ($action) {
  "pre-install" { Write-Output "Pre-install action" }
  "install" {
    Write-MajorStep "Install action"

    $tmpDir = [System.IO.Directory]::CreateTempSubdirectory($app + '-')
    $valuesFilePath = (Join-Path $tmpDir.FullName 'populated-values.yml')

    $valuesFileContent = Generate-Values $deploymentTarget.vars $environment $containerRegistryUrl $releaseTag $pullSecretName $project $valuesFilePath

    # monolith (and possibly other future apps) need to add additional value files to be set via --set-file
    # so let's see if there's an additional function to generate those.
    $additionalFiles = @()
    if ( Get-Command 'Generate-Additional-Values-Files' -errorAction SilentlyContinue ) { 
      Write-Host "Found additional values files"
      $additionalFiles = Generate-Additional-Values-Files $vars
    } 

    # The function is expected to return a dictionary-style entry where the key is the key of --set-file
    # and the value is the path to the file to be set.
    $setFileArgument = @()
    if ($additionalFiles.Count -gt 0) {
      $setFileArguments = @()
      # we need to form the --set-file command here to be used by helm so we iterate over each entry
      # and create an array of individual key=value strings to be joined later
      foreach ($entry in $additionalFiles.GetEnumerator()) {
        $setFileKey = $entry.Name
        $setFilePath = $entry.Value
        $setFileArguments += "$setFileKey=$setFilePath"
      }      
      $joinedArguments = $setFileArguments -join ","
      $setFileArgument = @('--set-file', $joinedArguments)
      Write-MinorStep "Additional files: $setFileArgument"
    }
    
    $valuesFileContent > $valuesFilePath

    $folder = Get-ChildItem -Path $env:PWD -Filter "charts" -Directory -Recurse | Select-Object -First 1
    
    if ($folder) {
      $folder = $folder.FullName
    }
    else {
      throw "No 'charts' folder found in the filesystem."
    }

    Write-MinorStep "Updating Helm dependencies..."
    Invoke-WithEcho helm dependency update --debug $folder/$app/     
    
    Write-Output "CNAB Folder: $folder"

    # Generate a Helm chart diff to the console output to see what changes will happen
    Write-MinorStep "Printing Helm diff..."
    Invoke-WithEcho helm diff upgrade --debug $app $folder/$app/ `
      -f $valuesFilePath `
      @setFileArgument `
      --namespace $app `
      --install `
      --normalize-manifests 
       
    # Invoke Helm upgrade
    Write-MinorStep "Running Helm upgrade..."
    Invoke-WithEcho helm upgrade --debug $app $folder/$app/ `
      -f $valuesFilePath `
      @setFileArgument `
      --namespace $app `
      --install `
      --create-namespace `
      --wait `
      --timeout 5m `
      @forceUpgrade

    Write-Output "$($PSStyle.Foreground.BrightGreen)Installation complete!$($PSStyle.Reset)"
  }

  "post-install" { Write-Output "Post-install action" }
  "uninstall" { Write-Output "Uninstall action" }
  "status" { Write-Output "Status action" }
  "human-intervention" {
    Write-Output "Human intervention action. Exiting with 5 as a test"
    exit 5
  }
  default { Write-Output "No action for $action" }
}

Write-Output "Action $action complete"