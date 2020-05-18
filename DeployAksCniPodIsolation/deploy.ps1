$resourceGroupNamme = "crgar-aks-isolated-winpods-rg"
$clusterName = "myAKSCluster"
$Location = "centralus"

$vnetName = "crgar-aks-isolated-winpods-vnet"
$podSubnetName = "PodsSubnets"
$servicesSubnetName = "ServicesSubnets"
$servicesSubnetNsg = "rgar-aks-isolated-pods-nsg"

# Create a resource group
az group create --name $resourceGroupNamme --location $Location

# Create a virtual network and subnet
az network vnet create `
    --resource-group $resourceGroupNamme `
    --name $vnetName `
    --address-prefixes 10.0.0.0/8 `
    --subnet-name $podSubnetName `
    --subnet-prefix 10.0.1.0/24

az network vnet subnet create  `
    --resource-group $resourceGroupNamme `
    --vnet-name $vnetName `
    -n $servicesSubnetName `
    --address-prefixes 10.0.2.0/24 
    #--network-security-group $servicesSubnetNsg

# Create a service principal and read in the application ID
$servicePrincipal = az ad sp create-for-rbac --output json
$servicePrincipalObj = $servicePrincipal | ConvertFrom-Json
$servicePrincipalId = $servicePrincipalObj.appId
$servicePrincipalPassword = $servicePrincipalObj.password

# Wait 15 seconds to make sure that service principal has propagated
echo "Waiting for service principal to propagate..."
sleep 15

# Get the virtual network resource ID
$vnetId = az network vnet show --resource-group $resourceGroupNamme --name $vnetName --query id -o tsv

# Assign the service principal Contributor permissions to the virtual network resource
az role assignment create --assignee $servicePrincipalId --scope $vnetId --role Contributor

# Get the virtual network subnet resource ID
$subnetId = az network vnet subnet show --resource-group $resourceGroupNamme --vnet-name $vnetName --name $podSubnetName --query id -o tsv

# Create the AKS cluster and specify the virtual network and service principal information
# Enable network policy by using the `--network-policy` parameter
az aks create `
    --resource-group $resourceGroupNamme `
    --name $clusterName `
    --node-count 1 `
    --generate-ssh-keys `
    --network-plugin azure `
    --service-cidr 10.0.3.0/24 `
    --dns-service-ip 10.0.0.10 `
    --docker-bridge-address 172.17.0.1/16 `
    --vnet-subnet-id $subnetId `
    --service-principal $servicePrincipalId `
    --client-secret $servicePrincipalPassword `
    --network-policy azure `
    --enable-addons monitoring