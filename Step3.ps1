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
    [string]$userscsv = "users.csv"
    )
## Dot source configuration variables:
try {
    $config_ps1 = Get-ChildItem -Path '.' -Filter "$config_ps1" -File -ErrorAction Stop
    Write-Host "Found $($config_ps1.fullname), dot-sourcing configuration variables.."

    . ".\$($config_ps1.name)"
}
catch {

    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Error reading searching for / dot sourcing config ps1, exiting script." -ForegroundColor Red
    Read-Host "Press enter to exit.."
    Return 1
}

## Import the users.csv file:
try {
    $user_info = Import-Csv -Path $userscsv
} catch {
    Write-host "Something went wrong importing the users.csv file.." -Foregroundcolor Yellow
    Read-Host "Press enter to exit.."
    Return 1
}

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Creating variables from $configjson JSON file."

## Variables from json file:
$DOMAIN_NAME = $DOMAIN_CONFIG.Name
$DC_PASSWORD = ConvertTo-SecureString $DOMAIN_CONFIG.Password -AsPlainText -Force
$DC_HOSTNAME = $DOMAIN_CONFIG.DC_hostname
$DOMAIN_NETBIOS = $DOMAIN_CONFIG.NetBIOS

## DHCP server variables:
$DHCP_IP_ADDR = $DHCP_SERVER_CONFIG.IP_Addr
$DHCP_SCOPE_NAME = $DHCP_SERVER_CONFIG.Scope.Name
$DHCP_START_RANGE = $DHCP_SERVER_CONFIG.Scope.Start
$DHCP_END_RANGE = $DHCP_SERVER_CONFIG.Scope.End
$DHCP_SUBNET_PREFIX = $DHCP_SERVER_CONFIG.Scope.subnet_prefix
$DHCP_GATEWAY = $DHCP_SERVER_CONFIG.Scope.gateway
$DHCP_DNS_SERVERS = $DHCP_SERVER_CONFIG.Scope.dns_servers

$DOMAIN_PATH = (Get-ADDomain).DistinguishedName

$BASE_OU = $USER_AND_GROUP_CONFIG.base_ou
## confirm base OU
Write-Host "Base OU is: " -nonewline
Write-Host "$BASE_OU" -foregroundcolor yellow
Write-Host "All users, groups, ous, etc. will be created inside this OU."
$reply = Read-Host "Proceed? [y/n]"
if ($reply.tolower() -eq 'y') {
    $null
} else {
    Write-Host "Script execution terminating now due to incorrect base OU: $Base_OU."
    Write-Host "You can change the base OU in the config.ps1 file (user_and_group_config variable)." -Foregroundcolor yellow
    Read-Host "Press enter to end."
    return 1
}

## DHCP
Install-WindowsFeature -Name DHCP -IncludeManagementTools

Restart-service dhcpserver

Add-DHCPServerInDC -DnsName "$DC_HOSTNAME.$DOMAIN_NAME" -IPAddress $DHCP_IP_ADDR

# DHCP Scope
Add-DHCPServerv4Scope -Name "$DHCP_SCOPE_NAME" -StartRange "$DHCP_START_RANGE" `
    -EndRange "$DHCP_END_RANGE" -SubnetMask $DHCP_SUBNET_PREFIX `
    -State Active

# Force specifies that the DNS server validation is skipped - since the current bash script has SNAT turned off for vnet.
Set-DHCPServerv4OptionValue -ComputerName "$DC_HOSTNAME.$DOMAIN_NAME" `
    -DnsServer $DHCP_DNS_SERVERS -DnsDomain "$DOMAIN_NAME" `
    -Router $DHCP_GATEWAY -Force

##
## Create OUs, users, and groups.
##

# Create a base 'homelab' OU, then OUs/groups from json inside.
try {
    New-ADOrganizationalUnit -Name "$BASE_OU" -Path "$DOMAIN_PATH" -ProtectedFromAccidentalDeletion $false
    Write-Host "Created $BASE_OU OU."
} catch {
    Write-Host "Something went wrong with creating $BASE_OU OU." -Foregroundcolor Red
}
## OUs/Groups created inside Base OU
$base_ou_path = (Get-ADOrganizationalUnit -Filter "Name -like '$base_ou'").DistinguishedName

## foreach listing in user_and_group_config that isn't the base ou - create an ou and group:
ForEach($listing in $($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -ne 'base_ou' })) {
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

        ForEach($single_group in $item_memberof) {
            Add-ADGroupMember -Identity $single_group -Members $item_name
            Write-Host "Added $item_name to $single_group."
        }

    } catch {
        Write-Host "Something went wrong with creating $item_name OU/Groups." -Foregroundcolor Red
    }
}

## Create users using users.csv\
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Creating users from $users_csv."

## Departmental OUs are created inside the users OU.
$users_ou_info = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? {$_.Name -eq 'users'}).value
$department_ou_path = (Get-ADOrganizationalUnit -Filter "Name -like '$($users_ou_info.name)'").DistinguishedName


## admin ou path
$admin_ou_info = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? {$_.Name -eq 'admins'}).value
$admin_ou_name = $admin_ou_info.name
$admin_ou_path = (Get-ADOrganizationalUnit -Filter "Name -eq '$admin_ou_name'").DistinguishedName

## First, need to create a group for each department listed in csv
ForEach ($unique_dept in $($user_info | select -exp department | select -unique)) {

    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Creating group for $unique_dept."
    try {
        New-ADGroup -Name $unique_dept -GroupCategory Security -GroupScope Global -Path "$department_ou_path" -Description "Departmental group for $unique_dept"
        Write-Host "Created departmental group: $unique_dept."
    } catch {
        Write-Host "Something went wrong with creating departmental group: $unique_dept." -Foregroundcolor Yellow
    }
}

ForEach ($user_account in $user_info) {
    $firstname = $user_account.firstname
    $lastname = $user_account.lastname
    $deptname = $user_account.department
    
    ## grab first 7 characters from last name
    if ($lastname.length -ge 8) {
        $username = $lastname.Substring(0, 8)
    }
    else {
        $username = $lastname
    }
    $username = "$($firstname[0])$username"

    ## password = $DC_PASSWORD

    $splat = @{
        SamAccountName    = $username
        UserPrincipalName = "$username@$DOMAIN_NAME"
        DisplayName       = "$firstname $lastname"
        Name              = $username
        GivenName         = $firstname
        Surname           = $lastname
        Department        = $deptname
        AccountPassword   = $DC_PASSWORD
        Enabled           = $true
        HomeDrive         = 'Z'
        HomeDirectory     = "\\$DC_HOSTNAME\users\$username"
        ProfilePath       = "\\$DC_HOSTNAME\profiles$\$username"
        Path = "$department_ou_path"
        # Force = $true
    }

    Write-Host "`nCreating user account for $firstname $lastname." -ForegroundColor Yellow
    # Write-Host "Username: $username"
    # Write-Host "Department: $deptname"
    try {
        New-ADUser @splat
        Write-Host "Created user: $($splat.userprincipalname)."
    } catch {
        Write-Host "Something went wrong creating user; $($splat.userprincipalname)." -foregroundcolor yellow
    }
    ## Add user to their dept group
    Add-ADGroupMember -Identity $deptname -Members $username

    Add-ADGroupMember -Identity $($user_ou_info.name) -Members $username ## need to make this identity variable/dynamic

    
    ## if they're an IT user - make them an admin
    if ($deptname -eq "IT") {

        $admin_username = "$($username)_admin"

        $admin_splat = @{
            SamAccountName    = $admin_username
            UserPrincipalName = "$admin_username@$DOMAIN_NAME"
            DisplayName       = "$firstname $lastname (admin)"
            Name              = $admin_username
            # GivenName         = $firstname
            # Surname           = $lastname
            Department        = $deptname
            AccountPassword   = $DC_PASSWORD
            Enabled           = $true
            Path              = "$admin_ou_path" ## explicit listing of the users group
        
        }
    
        Write-Host "`nCreating admin account for $firstname $lastname." -ForegroundColor Yellow
        Write-Host "Username: $admin_username"
        Write-Host "Department: $deptname"

        try {
            New-ADUser @admin_splat
            Write-Host "Created _admin user for: $($admin_splat.userprincipalname)."
        } catch {
            Write-Host "Something went wrong with creating user: $($admin_splat.userprincipalname)." -Foregroundcolor Yellow
        }
        ## Add user to their dept group
        Add-ADGroupMember -Identity $($admin_ou_info.name) -Members "$admin_username"

    }
}

## create file shares for folder redirection and roaming profiles, assign correct permissions for the users group created above.
If (-not (Test-Path C:\Shares -ErrorAction SilentlyContinue)) {
    New-Item -Path C:\Shares -ItemType Directory | Out-null
}

## Cycle through each fileshare object in $FILESHARE_CONFIG variable
ForEach($share_listing in $FILESHARE_CONFIG) {

    ## Get Admins group name:
    $admin_group_name = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? {$_.Name -eq 'admins'}).value
    $admin_group_name = $admin_group_name.name

    ## Get Users group name:
    $users_group_name = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? {$_.Name -eq 'users'}).value
    $users_group_name = $users_group_name.name

    $ShareParameters = @{
        Name                  = $share_listing.name
        Path                  = $share_listing.path
        Description           = $share_listing.description
        FullAccess            = "$DOMAIN_NETBIOS\Domain Admins", "$DOMAIN_NETBIOS\$admin_group_name", "Administrators" # explicit admin listing.
        ReadAccess            = "$DOMAIN_NETBIOS\$users_group_name"
        FolderEnumerationMode = "AccessBased"
        # ContinuouslyAvailable = $true
        # SecurityDescriptor = ""
    }

    ## Create directory if doesn't exist
    if (-not (Test-Path "$($share_listing.path)" -ErrorAction SilentlyContinue)) {
        New-Item -Path $share_listing.path -ItemType Directory | Out-Null
    }

    New-SmbShare @ShareParameters

    ## disbale inheritance, convert to explicit permissions
    ## disbale inheritance, convert to explicit permissions
    $acl = Get-Acl -Path $share_listing.path
    ## Add access rule for homelabusers group:
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("$DOMAIN_NETBIOS\$users_group_name", "ReadandExecute,CreateDirectories,AppendData,Traverse,ExecuteFile", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("$DOMAIN_NETBIOS\$admin_group_name", "FullControl", "Allow")))

    $acl.SetAccessRuleProtection($true, $true)

    Set-Acl -Path $share_listing.path -AclObject $acl

    ## Allows creation of user's folder in the share upon first login, users can't see other user folders.
    ## Ok for test lab.
    Grant-SMBshareAccess -Name $share_listing.name -AccountName "Authenticated Users" -AccessRight Full -Force

}
