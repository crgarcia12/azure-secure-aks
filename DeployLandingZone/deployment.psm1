function New-SecureAksLandingZone {
    [CmdletBinding()]
    param (
        [string] $Location = "eastus",
        [string] $AppName = "crgar-saks-us",
        [string] $SubscriptionName = 'crgar Internal Subscription'
    )    
        
    $context = Get-AzContext
    if (!$context.Account) {
        Connect-AzAccount -Subscription $SubscriptionName
    }

    # we don't want to deploy somewhere else
    Select-AzSubscription -Subscription $SubscriptionName -ErrorAction Stop

    $ResourceGroupName = "$AppName-rg"
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -ErrorAction SilentlyContinue
    New-AzResourceGroupDeployment  `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile 'template.json' `
        -Name "LandingZone" `
        -Mode Incremental `
        -appName $AppName
        
}

function Remove-SecureAksLandingZone {
    [CmdletBinding()]
    param (
        [string] $Location = "westeurope",
        [string] $AppName = "crgar-saks",
        [string] $SubscriptionName = 'crgar Internal Subscription'
    )   

    $ResourceGroupName = "$AppName-rg"
    Remove-AzResourceGroup -Name $ResourceGroupName -Force

}

Export-ModuleMember *