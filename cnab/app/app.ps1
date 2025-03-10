function Get-AppName() {
    $app = 'opserver'
    return $app
}

function Is-SingleRegistry() {
    return $True
}

function Generate-Values($vars, $environment, $containerRegistryUrl, $releaseTag, $pullSecretName) {
    Write-MajorStep "Generating Helm values"
    $values = @{
        tier                    = $environment
        replicaCount            = $vars.replicaCount
        aspnetcoreEnvironment   = $vars.aspnetcoreEnvironment
        product                 = "pubplat"

        db                      = @{
            exceptionalDbName = $vars.exceptionalDbName;
        }

        images                  = @{
            containerRegistry = "$containerRegistryUrl"
            opserver          = @{
                tag = $releaseTag
            }
        }

        requests                = @{
            cpu    = $vars.requestsCPU
            memory = $vars.requestsMemory
        }

        limits                  = @{
            memory = $vars.limitsMemory
        }

        podDisruptionBudget     = @{
            minAvailable = $vars.podDisruptionBudgetMinAvailable
        }

        exceptional             = @{
            store = @{
                type = $vars.exceptionalStoreType
            }
        }

        datadog                 = @{
            agentHost = $vars.datadogAgentHost
            agentPort = $vars.datadogAgentPort
        }

        kestrel                 = @{
            endPoints = @{
                http = @{
                    url           = "http://0.0.0.0:8080/"
                    containerPort = "8080"
                }
            }
        }

        secretStore             = @{
            fake = $vars.useFakeSecretStore
        }

        image                   = @{
            pullSecretName = $pullSecretName
        }

        ingress                 = @{
            className     = "nginx-internal"
            certIssuer    = "letsencrypt-dns-prod"
            host          = $vars.opserverSettings.hostUrl
            enabled       = $vars.includeIngress
            secretName    = "opserver-tls"
            createTlsCert = $true
        }

        sqlExternalSecret       = @{
            storeRefName = $vars.secretStore
        }

        configSecret       = @{
            storeRefName = $vars.secretStore
        }

        opserverExternalSecret  = @{
            storeRefName = $vars.secretStore
        }

        opserverSettings        = $vars.opserverSettings

        adminRolebindingGroupId = $vars.adminRolebindingGroupId

        nodeScheduling = @{
            # change to false if deploying locally to docker, or uninstall before installing the app to prevent node affinity issues
            scheduleOnSeparateNodes = $true
        }
    }



    # Helm expects a YAML file but YAML is also a superset of JSON, so we can use ConvertTo-Json here
    $valuesFileContent = $values | ConvertTo-Json -Depth 100
    Write-MinorStep "Populated Helm values:"
    Write-MinorStep $valuesFileContent
    return $valuesFileContent
}
