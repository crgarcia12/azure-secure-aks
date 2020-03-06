function Do-Everything
{
    $Prefix = "crgar-saks-us"
    $SubscriptionNAme = "crgar Internal Subscription"
    $Location = "eastus"


    $ServicePrincipalName = "crgar-saks-sp"
    $ResourceGroup = "${Prefix}-rg"
    $ClusterName = "${Prefix}20200304"
    $AcrName = "${Name}acr"
    $VnetName = "${Prefix}-vn-spoke"
    $AKSSubnetName = "${Prefix}-sn-spoke-aks-10.3.0.0_24"
    #$SvcSubnetName = "${Prefix}svcsubnet"
    $AciSubnetName = "${Prefix}-sn-spoke-aci-10.3.5.0_24"
    # DO NOT CHANGE FWSUBNET_NAME - This is currently a requirement for Azure Firewall.
    $FwSubnetName = "AzureFirewallSubnet"
    $AppGwSubnetName = "${Prefix}-sn-spoke-agw-10.3.3.0_24"
    $WorkspaceName = "${Prefix}k8slogs"
    $IdentityName = "${Prefix}identity"
    $FwName = "${Prefix}-fw-spoke"
    $FwPublicIpName = "${Prefix}-pip-fw-spoke"
    #$FwIpConfigName = "${Prefix}fwconfig"
    $FwRouteTableName = "${Prefix}-rt-spoke"
    $FwRouteName = "${Prefix}fwrn"
    $AgNAme = "${Prefix}-agw-spoke"
    $AgPublicIpName = "${Prefix}-pip-agw-spoke"
    $AksVersion = "1.15.7"
    



    Write-Verbose "Create SP and Assign Permission to Virtual Network"
    $ServicePrincipalJson = az ad sp create-for-rbac -n $ServicePrincipalName --skip-assignment
    $ServicePrincipal = $ServicePrincipalJson | ConvertFrom-Json
    Write-Verbose ($ServicePrincipal | Out-String)

    Write-Verbose "Getting the VNet ID"
    $VnetId = $(az network vnet show -g $ResourceGroup --name $VnetName --query id -o tsv)
    
    Write-Verbose "Assigning SP Permission to VNET"
    az role assignment create --assignee $ServicePrincipal.appId --scope $VnetId --role Contributor


    Write-Verbose "Populate the AKS Subnet ID - This is needed so we know which subnet to put AKS into"
    $SubnetId = $(az network vnet subnet show -g $ResourceGroup --vnet-name $VnetName --name $AKSSubnetName --query id -o tsv)

    Write-Verbose "Seting Workspace ID"
    $deployments = az group deployment list -g $ResourceGroup | Convertfrom-json    
    $WorkSpaceIdUrl = ($deployments.properties.outputResources | Where-Object -Property id -match "workspaces").id
    Write-Verbose "Workspace id: '$WorkSpaceIdUrl'"

    Write-Verbose "Creating AKS Cluster with Monitoring add-on using Service Principal '$($ServicePrincipal.name)'"
    az aks create -g $ResourceGroup `
        --name $ClusterName `
        -k $AksVersion `
        --location $Location `
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
        --no-wait `
        --debug


    
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
