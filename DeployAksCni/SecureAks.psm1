function New-SecureAksToolsInit {
    [CmdletBinding()]
    param (
        
    )

    # Add the Azure Firewall extension to Azure CLI in case you do not already have it.
    az extension add --name azure-firewall

}

function New-SecureAksDeploymentInLandingZone {
    [CmdletBinding()]
    param()

    $VerbosePreference = "Continue"
    #Start-Transcript -Path DeploymentLogs.log
    
    New-SecureAksEnvironmentVariables -Verbose
    New-SecureAksValidations -Verbose
    New-SecureAksServicePrincipal -Verbose
    New-SecureAksClusterDeployment -Verbose
    Get-SecureAksClusterCredentials -Verbose
    Test-SecureAksEgressTraffic -Verbose 
    
    #Stop-Transcript
}


function New-SecureAksFullDeployment {
    [CmdletBinding()]
    param()

    $VerbosePreference = Continue
    Start-Transcript -Path DeploymentLogs.txt

    New-SecureAksEnvironmentVariables
    New-SecureAksValidations
    New-SecureAksResourceGroup 
    New-SecureAksVNets
    New-SecureAksFirewallDeployment 
    New-SecureAksServicePrincipal
    New-SecureAksLogAnalyticsDeployment
    New-SecureAksClusterDeployment
    Get-SecureAksClusterCredentials
    Test-SecureAksEgressTraffic

    Stop-Transcript
}


function New-SecureAksEnvironmentVariables {
    [CmdletBinding()]
    param()

    # If running from a module, the path of the psm1 file, if running from the console, the path where to find yamls
    if ($PSCommandPath)
    {
        Set-Variable -Name DeployAksCniModulePath -Value (Split-Path $PSCommandPath) -Scope Global -Verbose
    } else {
        Set-Variable -Name DeployAksCniModulePath -Value "./DeployAksCni" -Scope Global -Verbose
    }


    Set-Variable -Name Prefix -Value "crgar-saks-eu" -Scope Global -Verbose
    Set-Variable -Name ResourceGroup -Value "${Prefix}-rg" -Scope Global -Verbose
    Set-Variable -Name Location -Value "westeurope" -Scope Global -Verbose
    Set-Variable -Name SubscriptionNAme -Value "crgar Internal Subscription" -Scope Global -Verbose
    
    Set-Variable -Name ClusterName -Value "${Prefix}-aks" -Scope Global -Verbose
    Set-Variable -Name ServicePrincipalName -Value "$Prefix-sp" -Scope Global -Verbose
    Set-Variable -Name AcrName -Value "${Name}acr" -Scope Global -Verbose
    Set-Variable -Name VnetName -Value "${Prefix}-vn-spoke" -Scope Global -Verbose
    Set-Variable -Name AKSSubnetName -Value "${Prefix}-sn-spoke-aks-10.3.0.0_24" -Scope Global -Verbose
    Set-Variable -Name SvcSubnetName -Value "${Prefix}svcsubnet" -Scope Global -Verbose
    Set-Variable -Name AciSubnetName -Value "${Prefix}-sn-spoke-aci-10.3.5.0_24" -Scope Global -Verbose
    # DO NOT CHANGE FWSUBNET_NAME - This is currently a requirement for Azure Firewall.
    Set-Variable -Name FwSubnetName -Value "AzureFirewallSubnet" -Scope Global -Verbose
    Set-Variable -Name AppGwSubnetName -Value "${Prefix}-sn-spoke-agw-10.3.3.0_24" -Scope Global -Verbose
    Set-Variable -Name WorkspaceName -Value "${Prefix}k8slogs" -Scope Global -Verbose
    Set-Variable -Name IdentityName -Value "${Prefix}identity" -Scope Global -Verbose
    Set-Variable -Name FwName -Value "${Prefix}-fw-spoke" -Scope Global -Verbose
    Set-Variable -Name FwPublicIpName -Value "${Prefix}-pip-fw-spoke" -Scope Global -Verbose
    Set-Variable -Name FwIpConfigName -Value "${Prefix}fwconfig" -Scope Global -Verbose
    Set-Variable -Name FwRouteTableName -Value "${Prefix}-rt-spoke" -Scope Global -Verbose
    Set-Variable -Name FwRouteName -Value "${Prefix}fwrn" -Scope Global -Verbose
    Set-Variable -Name AgNAme -Value "${Prefix}-agw-spoke" -Scope Global -Verbose
    Set-Variable -Name AgPublicIpName -Value "${Prefix}-pip-agw-spoke" -Scope Global -Verbose
    Set-Variable -Name AksVersion -Value "1.15.7" -Scope Global -Verbose

    Set-Variable -Name LogAnalyticsJsonFilePath -Value (Join-Path $DeployAksCniModulePath 'azuredeploy-loganalytics.json') -Scope Global -Verbose
    Set-Variable -Name CentosDeploymentYaml -Value (Join-Path $DeployAksCniModulePath 'centos-deployment.yaml') -Scope Global -Verbose

}

function New-SecureAksValidations {
    [CmdletBinding()]
    param (
        
    )

    if (!(Test-Path $LogAnalyticsJsonFilePath)) {
        Write-Error "Log Analytics deployment json not found in '$LogAnalyticsJsonFilePath'. Are you running this from the right path?"
    }

    Write-Verbose "Looking if version '$AksVersion' is supported in '$Location'. Available AKS versions:"
    az aks get-versions -l $Location -o table

    $AksOrchestratorVersions = (az aks get-versions -l $Location -o json | ConvertFrom-Json).orchestrators.orchestratorVersion
    if (!($AksOrchestratorVersions -contains $AksVersion))
    {
        Write-Error "Version '$AksVersion' not supported in '$Location'"
    }
    

}


function New-SecureAksResourceGroup {
    [CmdletBinding()]
    param ()

    # Get ARM Access Token and Subscription ID - This will be used for AuthN later.
    $AccessToken = $(az account get-access-token -o tsv --query 'accessToken')
    # NOTE: Update Subscription Name
    $SubscriptionId = $(az account show -s $SubscriptionNAme -o tsv --query 'id')
    # Create Resource Group
    az group create --name $ResourceGroup --location $Location
}

function New-SecureAksVNets {
    [CmdletBinding()]
    param ()

    az network vnet create `
        --resource-group $ResourceGroup `
        --name $VnetName `
        --address-prefixes 10.42.0.0/16 `
        --subnet-name $AksSubnetName `
        --subnet-prefix 10.42.1.0/24

    az network vnet subnet create `
        --resource-group $ResourceGroup `
        --vnet-name $VnetName `
        --name $SvcSubnetName `
        --address-prefix 10.42.2.0/24

    az network vnet subnet create `
        --resource-group $ResourceGroup `
        --vnet-name $VnetName `
        --name $AciSubnetName `
        --address-prefix 10.42.3.0/24

    az network vnet subnet create `
        --resource-group $ResourceGroup `
        --vnet-name $VnetName `
        --name $FwSubnetName `
        --address-prefix 10.42.4.0/24

    az network vnet subnet create `
        --resource-group $ResourceGroup `
        --vnet-name $VnetName `
        --name $AppGwSubnetName `
        --address-prefix 10.42.5.0/24
}

function New-SecureAksFirewallDeployment {
    [CmdletBinding()]
    param (
            
    )

    Write-Verbose "Creating Public IP for Azure Firewall"
    az network public-ip create -g $ResourceGroup -n $FwPublicIpName -l $Location --sku "Standard"

    Write-Verbose "Creating Azure Firewall"
    az network firewall create -g $ResourceGroup -n $FwName -l $Location

    Write-Verbose "Configuring Azure Firewall IP Config"
    az network firewall ip-config create -g $ResourceGroup -f $FwName -n $FwIpConfigName --public-ip-address $FwPublicIpName --vnet-name $VnetName

    Write-Verbose "Capture Azure Firewall IP Address for Later Use"
    $FwPublicIp = $(az network public-ip show -g $ResourceGroup -n $FwPublicIpName --query "ipAddress" -o tsv)
    $FwPrivateIp = $(az network firewall show -g $ResourceGroup -n $FwName --query "ipConfigurations[0].privateIpAddress" -o tsv)

    Write-Verbose "Validate Azure Firewall IP Address Values"
    Write-Verbose "Public Ip: $FwPublicIp"
    Write-Verbose "Private Ip: $FwPrivateIp"

    Write-Verbose "Creating UDR & Routing Table for Azure Firewall"
    az network route-table create -g $ResourceGroup --name $FwRouteTableName
    az network route-table route create -g $ResourceGroup --name $FwRouteName --route-table-name $FwRouteTableName --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FwPrivateIp --subscription $SubscriptionId

    Write-Verbose "Adding Network FW Rules for egress traffic"
    # TCP - * - * - 22
    # TCP - * - * - 443
    # If you want to lock down destination IP Addresses you will have to use the destination IP Addresses for the datacenter region you are deploying into, see note from above.
    # For Example: East US DC Destination IP Addresses: 13.68.128.0/17,13.72.64.0/18,13.82.0.0/16,13.90.0.0/16,13.92.0.0/16,20.38.98.0/24,20.39.32.0/19,20.42.0.0/17,20.185.0.0/16,20.190.130.0/24,23.96.0.0/17,23.98.45.0/24,23.100.16.0/20,23.101.128.0/20,40.64.0.0/16,40.71.0.0/16,40.76.0.0/16,40.78.219.0/24,40.78.224.0/21,40.79.152.0/21,40.80.144.0/21,40.82.24.0/22,40.82.60.0/22,40.85.160.0/19,40.87.0.0/17,40.87.164.0/22,40.88.0.0/16,40.90.130.96/28,40.90.131.224/27,40.90.136.16/28,40.90.136.32/27,40.90.137.96/27,40.90.139.224/27,40.90.143.0/27,40.90.146.64/26,40.90.147.0/27,40.90.148.64/27,40.90.150.32/27,40.90.224.0/19,40.91.4.0/22,40.112.48.0/20,40.114.0.0/17,40.117.32.0/19,40.117.64.0/18,40.117.128.0/17,40.121.0.0/16,40.126.2.0/24,52.108.16.0/21,52.109.12.0/22,52.114.132.0/22,52.125.132.0/22,52.136.64.0/18,52.142.0.0/18,52.143.207.0/24,52.146.0.0/17,52.147.192.0/18,52.149.128.0/17,52.150.0.0/17,52.151.128.0/17,52.152.128.0/17,52.154.64.0/18,52.159.96.0/19,52.168.0.0/16,52.170.0.0/16,52.179.0.0/17,52.186.0.0/16,52.188.0.0/16,52.190.0.0/17,52.191.0.0/18,52.191.64.0/19,52.191.96.0/21,52.191.104.0/27,52.191.105.0/24,52.191.106.0/24,52.191.112.0/20,52.191.192.0/18,52.224.0.0/16,52.226.0.0/16,52.232.146.0/24,52.234.128.0/17,52.239.152.0/22,52.239.168.0/22,52.239.207.192/26,52.239.214.0/23,52.239.220.0/23,52.239.246.0/23,52.239.252.0/24,52.240.0.0/17,52.245.8.0/22,52.245.104.0/22,52.249.128.0/17,52.253.160.0/24,52.255.128.0/17,65.54.19.128/27,104.41.128.0/19,104.44.91.32/27,104.44.94.16/28,104.44.95.160/27,104.44.95.240/28,104.45.128.0/18,104.45.192.0/20,104.211.0.0/18,137.116.112.0/20,137.117.32.0/19,137.117.64.0/18,137.135.64.0/18,138.91.96.0/19,157.56.176.0/21,168.61.32.0/20,168.61.48.0/21,168.62.32.0/19,168.62.160.0/19,191.233.16.0/21,191.234.32.0/19,191.236.0.0/18,191.237.0.0/17,191.238.0.0/18
    # Create the Outbound Network Rule from Worker Nodes to Control Plane
    az network firewall network-rule create -g $ResourceGroup -f $FwName --collection-name 'aksfwnr' -n 'ssh' `
     --protocols 'TCP' `
     --source-addresses '*' `
     --destination-addresses '*' `
     --destination-ports 22 443 123 9000`
     --action allow `
     --priority 100

    Write-Verbose "Adding Application FW Rules for egress traffic"
    $priority = 100
    # Check https://docs.microsoft.com/en-us/azure/aks/limit-egress-traffic
    az network firewall application-rule create -g $ResourceGroup -f $FwName --collection-name 'aksfwar-required' -n 'AKS' --source-addresses '*' `
        --protocols 'http=80' 'https=443' --action allow --priority $($priority+=100;$priority) `
        --target-fqdns `
            '*.azmk8s.io' `
            'mcr.microsoft.com' `
            '*.cdn.mscr.io' `
            'management.azure.com' `
            'login.microsoftonline.com' `
            'ntp.ubuntu.com' `
            'packages.microsoft.com' `
            'acs-mirror.azureedge.net'

    az network firewall application-rule create -g $ResourceGroup -f $FwName --collection-name 'aksfwar-ubuntu-updates' -n 'AKS' --source-addresses '*' `
        --protocols 'http=80' 'https=443' --action allow --priority $($priority+=100;$priority) `
        --target-fqdns `
            'security.ubuntu.com' `
            'azure.archive.ubuntu.com' `
            'changelogs.ubuntu.com'

    az network firewall application-rule create -g $ResourceGroup -f $FwName --collection-name 'aksfwar-azure-monitor' -n 'AKS' --source-addresses '*' `
        --protocols 'http=80' 'https=443' --action allow --priority $($priority+=100;$priority) `
        --target-fqdns `
            'dc.services.visualstudio.com' `
            '*.ods.opinsights.azure.com' `
            '*.oms.opinsights.azure.com' `
            '*.microsoftonline.com' `
            '*.monitoring.azure.com'

    az network firewall application-rule create -g $ResourceGroup -f $FwName --collection-name 'aksfwar-azure-policies' -n 'AKS' --source-addresses '*' `
        --protocols 'http=80' 'https=443' --action allow --priority $($priority+=100;$priority) `
        --target-fqdns `
            'gov-prod-policy-data.trafficmanager.net' `
            'raw.githubusercontent.com' `
            '*.azmk8s.io' `
            'dc.services.visualstudio.com'

    az network firewall application-rule create -g $ResourceGroup -f $FwName --collection-name 'aksfwar-crgar-others' -n 'AKS' --source-addresses '*' `
        --protocols 'http=80' 'https=443' --action allow --priority $($priority+=100;$priority) `
        --target-fqdns `
            'k8s.gcr.io' `
            'storage.googleapis.com' `
            '*eastus.azmk8s.io' `
            '*auth.docker.io' `
            '*cloudflare.docker.io' `
            '*cloudflare.docker.com' `
            '*registry-1.docker.io' `
            '*.ubuntu.com' `
            '*azurecr.io' `
            '*mcr.microsoft.com' `
            '*cdn.mscr.io'


    Write-Verbose "Associating AKS Subnet to Azure Firewall"
    az network vnet subnet update -g $ResourceGroup --vnet-name $VnetName --name $AksSubnetName --route-table $FwRouteTableName
    # OR if you know the Subnet ID and would prefer to do it that way.
    #az network vnet subnet show -g $RG --vnet-name $VNET_NAME --name $AKSSUBNET_NAME --query id -o tsv
    #SUBNETID=$(az network vnet subnet show -g $RG --vnet-name $VNET_NAME --name $AKSSUBNET_NAME --query id -o tsv)
    #az network vnet subnet update -g $RG --route-table $FWROUTE_TABLE_NAME --ids $SUBNETID

    Write-Verbose "Enabling monitoring to Azure Firewall"
    # We need to escape quotes like this when running this command from Powershell
    # http://mitzen.blogspot.com/2019/07/powershell-passing-json-string-into-az.html
    $logs = '[{\"category\": \"AzureFirewallApplicationRule\",\"enabled\": true},{\"category\": \"AzureFirewallNetworkRule\",\"enabled\": true}]'
    $metrics = '[{\"category\": \"AllMetrics\",\"enabled\": true}]'
    az monitor diagnostic-settings create `
        --name "$Prefix-fw-monitoring-settings" `
        --resource "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Network/azureFirewalls/$FwName" `
        --workspace $WorkspaceName `
        --logs $logs `
        --metrics $metrics
}

function New-SecureAksServicePrincipal {
    [CmdletBinding()]
    param (

    )

    Write-Verbose "Create SP and Assign Permission to Virtual Network"
    $ServicePrincipalJson = az ad sp create-for-rbac -n "${Prefix}sp" --skip-assignment
    $ServicePrincipal = $ServicePrincipalJson | ConvertFrom-Json
    Write-Verbose ($ServicePrincipalJson | Out-String)

    Write-Verbose "Getting the VNet ID"
    $VnetId = $(az network vnet show -g $ResourceGroup --name $VnetName --query id -o tsv)
    
    Write-Verbose "Assigning SP Permission to VNET"
    az role assignment create --assignee $ServicePrincipal.appId --scope $VnetId --role Contributor
}

function New-SecureAksLogAnalyticsDeployment {
    [CmdletBinding()]
    param (
        
    )


    Write-Verbose "Creating Log Analytics Workspace"
    az group deployment create -n $WorkSpaceName -g $ResourceGroup `
        --template-file $LogAnalyticsJsonFilePath `
        --parameters workspaceName=$WorkSpaceName `
        --parameters location=$Location `
        --parameters sku="Standalone"

}


function New-SecureAksClusterDeployment {
    [CmdletBinding()]
    param (
        
    )

    Write-Verbose "Available versions:"
    az aks get-versions -l $Location -o table

    Write-Verbose "Populate the AKS Subnet ID"
    $SubnetId = $(az network vnet subnet show -g $ResourceGroup --vnet-name $VnetName --name $AKSSubnetName --query id -o tsv)
    Write-Verbose "Subnet '$SubnetId' will be used to allocate AKS"

    Write-Verbose "Seting Workspace ID"
    $deployments = az group deployment list -g $ResourceGroup | Convertfrom-json    
    $WorkSpaceIdUrl = ($deployments.properties.outputResources | Where-Object -Property id -match "workspaces").id
    Write-Verbose "Workspace id: '$WorkSpaceIdUrl'"

    Write-Verbose "Creating AKS Cluster with Monitoring add-on using Service Principal '$($ServicePrincipal.name)'"
    az aks create -g $ResourceGroup `
        -n $ClusterName `
        -k $AksVersion `
        -l $Location `
        --node-count 2 `
        --generate-ssh-keys `
        --enable-addons monitoring `
        --workspace-resource-id $WorkSpaceIdUrl `
        --network-plugin azure `
        --network-policy azure `
        --service-cidr 10.41.0.0/16 `
        --dns-service-ip 10.41.0.10 `
        --docker-bridge-address 172.17.0.1/16 `
        --vnet-subnet-id $SubnetId `
        --service-principal $ServicePrincipal.appId `
        --client-secret $ServicePrincipal.password `
        --no-wait

    # Check Provisioning Status of AKS Cluster - ProvisioningState should say 'Succeeded'
    $ClusterReady = $false
    while(!$ClusterReady) {

        Start-Sleep -Seconds 1
        Write-Verbose "Waiting for cluster '$ClusterName' to be created"
        $clusters = az aks list -o json | ConvertFrom-Json
        $cluster = $clusters | Where-Object -Property name -EQ $ClusterName
        $ClusterReady = $cluster.provisioningState -ne "Creating"
        
        Write-Verbose "Cluster '$ClusterName' is in provisioningState '$($cluster.provisioningState)'"
    }

    if ($cluster.provisioningState -ne "Succeeded")
    {
        Write-Error "Cluster provisioningState is '$($cluster.provisioningState)'. Expected 'Succeeded'"
    }

}

function Get-SecureAksClusterCredentials {
    [CmdletBinding()]
    param (
    
    )

    Write-Verbose "Geting AKS Credentials so kubectl works"
    az aks get-credentials -g $ResourceGroup -n $ClusterName --admin

    Write-Verbose "Geting Nodes"
    kubectl get nodes -o wide
}

function New-SecureAksApplicationGateway {
    [CmdletBinding()]
    param (
        
    )
    
    # Create Azure App Gateway v2 with WAF and autoscale set to manual.
    # NOTE: Azure App Gateway v2 is currently in Preview. Also note that it is not possible at this time
    # to create an Azure App Gateway with WAF enabled without a Public IP.
    Write-Verbose "Creating Public IP needed for Azure Application Gateway - This is needed due to WAF"
    az network public-ip create -g $ResourceGroup -n $AgPublicIpName -l $Location --sku "Standard"

    # Create App Gateway using WAF_v2 SKU - This will take several minutes so be patient.
    az network application-gateway create `
        --name $AgNAme `
        --resource-group $ResourceGroup `
        --location $Location `
        --min-capacity 2 `
        --capacity 2 `
        --frontend-port 80 `
        --http-settings-cookie-based-affinity Disabled `
        --http-settings-port 80 `
        --http-settings-protocol Http `
        --routing-rule-type Basic `
        --sku WAF_v2 `
        --private-ip-address 10.42.5.12 `
        --public-ip-address $AgPublicIpName `
        --subnet $AppGwSubnetName `
        --vnet-name $VnetName
}

function Test-SecureAksEgressTraffic {
    [CmdletBinding()]
    param (
        
    )
    
    kubectl apply -f $CentosDeploymentYaml 
    kubectl get po -o wide

    try {
        $url = "packages.microsoft.com"
        Write-Verbose "Testing connection to '$url'"
        $response = kubectl exec -it centos -- curl $url
        if(!($response -contains "<html>"))
        {
            Write-Error "Cluster has no connection to required services"
        } else {
            Write-Verbose "'$url' could be accessed from Pod"
        }

        $url = "google.com"
        Write-Verbose "Testing connection to '$url'"
        $response = kubectl exec -it centos -- curl $url
        if(!($response -contains "<html>") -and ($response -contains "Action: Deny."))
        {
            Write-Error "Cluster has connection to the internet!"
        } else {
            Write-Verbose "Internet not accessible: '$url' denied"
        }
    } finally {
        kubectl delete pod centos
    }
}

function Get-SecureAksCliTerminal {
    [CmdletBinding()]
    param (
        
    )
    
    kubectl apply -f $CentosDeploymentYaml 
    kubectl get po -o wide
    kubectl exec -it centos -- /bin/bash

}


function Open-SecureAksDashboard {
    [CmdletBinding()]
    param (
        
    )
    
    az aks browse -g $ResourceGroup -n $ClusterName
}



Export-ModuleMember *SecureAks*