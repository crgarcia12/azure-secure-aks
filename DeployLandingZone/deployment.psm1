function New-SecureAksLandingZone {
    [CmdletBinding()]
    param (
        [string] $Location = "westeurope",
        [string] $AppName = "crgar-saks-eu",
        [string] $SubscriptionName = 'crgar Internal Subscription'
    )    
        
    $TemplateJsonFilePath = Join-Path (Split-Path $PSCommandPath) 'template.json'


    $context = (az account show | ConvertFrom-Json).name
    if (!$context) {
        az login
    }

    # we don't want to deploy somewhere else
    Select-AzSubscription -Subscription $SubscriptionName -ErrorAction Stop

    $ResourceGroupName = "$AppName-rg"
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -ErrorAction SilentlyContinue
    New-AzResourceGroupDeployment  `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $TemplateJsonFilePath  `
        -Name "LandingZone" `
        -Mode Incremental `
        -appName $AppName
        
}

function Remove-SecureAksLandingZone {
    [CmdletBinding()]
    param (
        [string] $Location = "westeurope",
        [string] $AppName = "crgar-saks-eu",
        [string] $SubscriptionName = 'crgar Internal Subscription'
    )   

    $ResourceGroupName = "$AppName-rg"
    Remove-AzResourceGroup -Name $ResourceGroupName -Force

}

Export-ModuleMember *