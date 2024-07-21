## AD Home/Test Lab Setup Scripts - Step 2
## Step 2 installs AD-Domain-Services feature.
## Author: Alex B.
## https://github.com/albddnbn/powershellnexusone
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1 = "config.ps1"
)
## Dot source configuration variables:
try {
    $config_ps1 = Get-ChildItem -Path './config' -Filter "$config_ps1_filename" -File -ErrorAction Stop
    Write-Host "Found $($config_ps1.fullname), dot-sourcing configuration variables.."

    . "$($config_ps1.fullname)"
}
catch {

    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Error reading searching for / dot sourcing config ps1, exiting script." -ForegroundColor Red
    Read-Host "Press enter to exit.."
    Return 1
}

## Get rid of the scheduled task for this script
Get-ScheduledTask | ? { $_.TasKName -like "step2*adlab" } | Unregister-ScheduledTask -Confirm:$false

## create scheduled task for step3.ps1:
$step3_filepath = (get-item ./step3.ps1).fullname
. ./create_scheduled_task.ps1 -task_name 'step3_genadlab' -task_file_path "$step3_filepath"

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Creating variables from $configjson JSON file."
## Variables from json file:
$DOMAIN_NAME = $DOMAIN_CONFIG.Name
$DC_PASSWORD = ConvertTo-SecureString $DOMAIN_CONFIG.Password -AsPlainText -Force

## List the variables created above with get0-date timestampe
# Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Variables created from $($config_json):"
Write-Host "DOMAIN_NAME:        $DOMAIN_NAME"
Write-Host "DC_PASSWORD:        ...."

Write-Host "Installing AD DS.."

## Install AD DS
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Write-Host "Creating new AD DS Forest.."
Install-ADDSForest -DomainName $DOMAIN_NAME -DomainMode WinThreshold -ForestMode WinThreshold `
    -InstallDns -SafeModeAdministratorPassword $DC_PASSWORD -Force -Confirm:$false

## System should reboot automatically here?
read-host "if system hasn't rebooted, press enter to reboot.."
Restart-Computer -Force