[CmdletBinding()]
param (
    [ValidateSet("pre-install", "install")]
    [string]
    $Action = "install",
    [bool]
    $RunAsContainer = $false,
    [ValidateSet("GCP", "DockerDesktop")]
    [string]
    $Target = "GCP",
    [bool]
    $DownloadLocalScriptsForLocalDebugging = $true
)

# Function to check if a command exists
function Check-CommandExists {
    param (
        [string]$Command
    )

    if ($null -eq (Get-Command "$Command.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "Unable to find $Command. Please install $Command before continuing"
        exit 1
    }
}

function Setup-GCP {
    Check-CommandExists -Command "gcloud-crc32c"

    # Check if user is signed in to gcloud
    $gcloudAuthStatus = gcloud auth list --format="value(account)"
    if (-not $gcloudAuthStatus) {
        & gcloud auth login
    }
}

function Setup-DockerDesktop {
    Check-CommandExists -Command "kubectl"
    Check-CommandExists -Command "helm"

    & kubectl config use-context "docker-desktop"

    Write-Host "Check if Kubernetes is enabled in Docker Desktop"
    $output = & kubectl get node docker-desktop  2>&1 | Out-String

    if ( $output.Trim() -eq "Unable to connect to the server: EOF") {
        Write-Error "Kubernetes is not enabled in Docker Desktop. Please enable Kubernetes before continuing or change the target."
        exit 1
    }

    Write-Host "Kubernetes is enabled in Docker Desktop"
    
    $repoExists = (helm repo list | Select-String -Pattern "external-secrets")
    $chartExists = (helm list -n local-external-secrets | Select-String -Pattern "external-secrets")

    if (-not $repoExists) {
        Write-Host "Adding external-secrets repo to Kubernetes"
        & helm repo add external-secrets https://charts.external-secrets.io
    }

    if (-not $chartExists) {
        Write-Host "Adding external-secrets chart to Kubernetes"
        & helm repo update
        & helm install external-secrets external-secrets/external-secrets -n local-external-secrets --create-namespace --set installCRDs=true
    }
}

$MetaJsonPath = "$PSScriptRoot/app/variables.$Target.json"

if (-not (Test-Path $MetaJsonPath)) {
    Write-Error "File not found: $MetaJsonPath"
    exit 1
}

if ($Target -eq "DockerDesktop") {
    Setup-DockerDesktop
 
     # Build local app images for Docker Desktop
     if (Test-Path "$PSScriptRoot/app/build-app-image.ps1") {
        . "$PSScriptRoot/app/build-app-image.ps1"
    }
    else {
        Write-Error "File not found: $PSScriptRoot/app/build-app-image.ps1"
        exit 1
    }
    
    if ( Get-Command 'Build-Local-App-Image' -errorAction SilentlyContinue ) { 
        Build-Local-App-Image
    } 
    else {
        Write-Warning "Cannot find function Build-Local-App-Image in build-app-image.ps1. Assuming local images exists and can be used by Docker Desktop."
    }
}
elseif ($Target -eq "GCP") {
    Setup-GCP
}

if ($RunAsContainer) {
    $appScriptPath = "$PSScriptRoot/app/app.ps1"
    if (Test-Path $appScriptPath) {
        . $appScriptPath
    }
    else {
        Write-Error "File not found: $appScriptPath"
        exit 1
    }

    if (Get-Command 'Get-AppName' -ErrorAction SilentlyContinue) {
        $appName = Get-AppName
    }
    else {
        Write-Error "Function Get-AppName not found. Please define the function before continuing."
        exit 1
    }
    
    $CNABImage = "$appName-cnab:local"
    # Build a local copy of CNAB image
    docker build -t $CNABImage -f $PSScriptRoot/build/Dockerfile .

    $dockerRunArgs = @()

    if ($Target -eq "GCP") {
        # Get current config path
        $gcloudConfigDir = gcloud info --format='value(config.paths.global_config_dir)'
        $dockerRunArgs += @(
            "-v", "$($gcloudConfigDir):/root/.config/gcloud",
            "--env", "GOOGLE_APPLICATION_CREDENTIALS=/gcp/creds.json"
        )
    }
    elseif ($Target -eq "DockerDesktop") {

    
        if ($IsWindows) {
            $kubeConfigPath = "$env:USERPROFILE\.kube\config"
        }
        else {
            $kubeConfigPath = "~/.kube/config"
        }

        $dockerRunArgs += @(
            "-v", "$($kubeConfigPath):/.kube/config:ro",
            "--env", "KUBECONFIG=/.kube/config"
        )
    }

    $dockerRunArgs += @(
        "-v", "$($MetaJsonPath):/variables.json",
        "--env", "CNAB_ACTION=$Action",
        "--env", "INSTALLATION_METADATA=/variables.json",
        "--rm", "$CNABImage", "/cnab/app/run.ps1"
    )

    docker run $dockerRunArgs
}
else {

    $env:CNAB_ACTION = $Action
    $env:INSTALLATION_METADATA = $MetaJsonPath
    
    if ($DownloadLocalScriptsForLocalDebugging) {
        # Read the CNAB base image from the Dockerfile
        $DockerfilePath = "$PSScriptRoot/build/Dockerfile"
        if (-not (Test-Path $DockerfilePath)) {
            Write-Error "Dockerfile not found: $DockerfilePath"
            exit 1
        }

        $CNABBaseImage = Select-String -Path $DockerfilePath -Pattern "^FROM\s+(.*)" | ForEach-Object { $_.Matches[0].Groups[1].Value }
        if (-not $CNABBaseImage) {
            Write-Error "Unable to find the base image in the Dockerfile"
            exit 1
        }
 
        # Run the CNAB base image container to copy required files
        $containerId = docker run -d --rm $CNABBaseImage tail -f /dev/null
        docker cp "${containerId}:/cnab/app/" "$PSScriptRoot\"
        docker rm -f $containerId
    }

    & "$PSScriptRoot\app\run.ps1"
}