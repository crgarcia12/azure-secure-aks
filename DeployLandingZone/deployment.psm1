function New-SecureAksLandingZone {
    [CmdletBinding()]
    param (
        [string] $Location = "westeurope",
        [string] $ResourceGroupName = "crgar-appSaks",
        [string] $SubscriptionName = 'crgar Internal Subscription'
    )    
        
    $context = Get-AzContext
    if(!$context.Account)
    {
        Connect-AzAccount -Subscription $SubscriptionName
    }

    # we don't want to deploy somewhere else
    Select-AzSubscription -Subscription $SubscriptionName -ErrorAction Stop

    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -ErrorAction SilentlyContinue
    New-AzResourceGroupDeployment  `
        -ResourceGroupName $ResourceGroupName 
        -TemplateFile 'template.json' `
        -Name "LandingZone" `
        -Mode Incremental `
        -appName "crgar-appSaks"
        
}

Export-ModuleMember *