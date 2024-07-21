## AD Home/Test Lab Setup Scripts - Step 3
## Step 3 Installs and configures DHCP server/settings. Then, creates OU structure and users.
## Author: Alex B.
## https://github.com/albddnbn/powershellnexusone
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1 = "config.ps1",
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    [string]$user_creation_ps1_file = "create_user_population.ps1",
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    [string]$fileshares_ps1_file = "create_fileshares.ps1"
)
## Make sure user creation script can be accessed:
$user_creation_script = Get-ChildItem -Path './config' -Filter "$user_creation_ps1_file" -File -ErrorAction Stop
$fileshare_creation_script = Get-ChildItem -Path './config' -Filter "$fileshares_ps1_file" -File -ErrorAction Stop

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

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Creating variables from $configjson JSON file."

## Variables from json file: 
$DOMAIN_NAME = (Get-ADDomain).DNSRoot
$DOMAIN_PATH = (Get-ADDomain).DistinguishedName

$DC_HOSTNAME = (Get-ADDomainController).HostName

## DHCP server variables:
$DHCP_IP_ADDR = $DHCP_SERVER_CONFIG.IP_Addr
$DHCP_SCOPE_NAME = $DHCP_SERVER_CONFIG.Scope.Name
$DHCP_START_RANGE = $DHCP_SERVER_CONFIG.Scope.Start
$DHCP_END_RANGE = $DHCP_SERVER_CONFIG.Scope.End
$DHCP_SUBNET_PREFIX = $DHCP_SERVER_CONFIG.Scope.subnet_prefix
$DHCP_GATEWAY = $DHCP_SERVER_CONFIG.Scope.gateway
$DHCP_DNS_SERVERS = $DHCP_SERVER_CONFIG.Scope.dns_servers


$BASE_OU = $USER_AND_GROUP_CONFIG.base_ou
## confirm base OU
Write-Host "Base OU is: " -nonewline
Write-Host "$BASE_OU" -foregroundcolor yellow
Write-Host "All users, groups, ous, etc. will be created inside this OU."
# $reply = Read-Host "Proceed? [y/n]"
# if ($reply.tolower() -eq 'y') {
#     $null
# }
# else {
#     Write-Host "Script execution terminating now due to incorrect base OU: $Base_OU."
#     Write-Host "You can change the base OU in the config.ps1 file (user_and_group_config variable)." -Foregroundcolor yellow
#     Read-Host "Press enter to end."
#     return 1
# }

##
## DHCP setup / configuration of single scope
##

Install-WindowsFeature -Name DHCP -IncludeManagementTools

Restart-service dhcpserver

Add-DHCPServerInDC -DnsName "$DC_HOSTNAME.$DOMAIN_NAME" -IPAddress $DHCP_IP_ADDR

# DHCP Scope
Add-DHCPServerv4Scope -Name "$DHCP_SCOPE_NAME" -StartRange "$DHCP_START_RANGE" `
    -EndRange "$DHCP_END_RANGE" -SubnetMask $DHCP_SUBNET_PREFIX `
    -State Active

# Force specifies that the DNS server validation is skipped - since the current bash script has SNAT turned off for vnet.
Set-DHCPServerv4OptionValue -ComputerName "$DC_HOSTNAME" `
    -DnsServer $DHCP_DNS_SERVERS -DnsDomain "$DOMAIN_NAME" `
    -Router $DHCP_GATEWAY -Force

##
## OU and Group Creation
##

## Create BASE OU using value from config.ps1 (all new users / groups / ous will be created inside this OU for easy removal)
try {
    New-ADOrganizationalUnit -Name "$BASE_OU" -Path "$DOMAIN_PATH" -ProtectedFromAccidentalDeletion $false
    Write-Host "Created $BASE_OU OU."

    ## OUs/Groups created inside Base OU
    $base_ou_path = (Get-ADOrganizationalUnit -Filter "Name -eq '$base_ou'").DistinguishedName
}
catch {
    Write-Host "Something went wrong with creating $BASE_OU OU." -Foregroundcolor Red
    Write-Host "You can change the base OU in the config.ps1 file (user_and_group_config variable)." -Foregroundcolor yellow
    Read-Host "Press enter to end."
    return 1
}

## This will create an AD Group and OU for each listing in the user_and_group_config variable, except for the base_ou listing.
## By default - a group for regular users, IT admins, and computers is included.
ForEach ($listing in $($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -ne 'base_ou' })) {
    ## Used for OU and Group Name
    $item_name = $listing.value.name
    ## Used for Group Description
    $item_description = $listing.value.description
    ## The group created is added to groups in memberof property
    $item_memberof = $listing.value.memberof
    try {
        New-ADOrganizationalUnit -Name $item_name -Path "$base_ou_path" -ProtectedFromAccidentalDeletion $false
        Write-Host "Created $item_name OU."

        $ou_path = (Get-ADOrganizationalUnit -Filter "Name -like '$item_name'").DistinguishedName

        New-ADGroup -Name $item_name -GroupCategory Security -GroupScope Global -Path "$ou_path" -Description "$item_description"

        Write-Host "Created group: $item_name."

        ForEach ($single_group in $item_memberof) {
            Add-ADGroupMember -Identity $single_group -Members $item_name
            Write-Host "Added $item_name to $single_group."
        }
    }
    catch {
        Write-Host "Something went wrong with creating $item_name OU/Groups." -Foregroundcolor Red
    }
}

##
## AD User / Admin user creation
## All users in the IT department receive an _admin account.


## Create users using users.csv\
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Beginning user creation."

Powershell.exe -ExecutionPolicy Bypass "$($user_creation_script.fullname)"


## Create file shares
Powershell.exe -ExecutionPolicy Bypass "$($fileshare_creation_script.fullname)"

Get-ScheduledTask -Name 'step3_genadlab' | Unregister-ScheduledTask -Confirm:$false

