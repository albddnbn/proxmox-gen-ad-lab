# proxmox-gen-ad-lab
A collection of bash/powershell scripts to generate an Active Directory lab in Proxmox.
*Alex B.*

## Basic usage:

### First, run gen_vnet_vm.sh
<b>VMs created using this script prompt for many values, but some settings are explicitly hard-coded based on recommendations from various articles, like this one: https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/</b>

gen_vnet_vm.sh will do a few things:

1. Virtual network/gateway through the use of Proxmox's SDN feature with ability to switch Internet access on/off instantaneously.
2. VM in Proxmox using combination of configuration variables and known-good settings. At this point, the script will target the specified storage drive and list a menu of iso's. This allows the user to select their Windows Server iso, and then the VirtIO iso containing drivers necessary to use certain storage types.
3. Using a template and Proxmox's built-in API, basic firewall rules necessary for an Active Directory domain controller are applied to the VM created and enabled.

### Second, run the Powershell scripts in order of their 'step' number, on the domain controller VM:

#### Step 1:
- domain controller's hostname, static IP address info, DNS Settings
- script will search attached drives for virtio msi installer (necessary for usage of virtio virtual hardware devices including network adapter)

#### Step 2:
- Installs AD DS with DNS server
- configures new AD DS Forest and Domain Controller role

#### Step 3:
- Installs and configures DHCP Server with single DHCP scope
- Creates AD DS OUs, Groups, Users
- Creates file shares for roaming profiles/folder redirection and configures permissions

## Configuration
You can configure Active Directory domain-related settings in the config.ps1 file. This file is dot-sourced at the beginning of each of the 'step' scripts to introduce the configuration variables. I decided to use a .ps1 file / variables for configuration rather than a JSON, so that I could easily comment and add instructions to the config file.

## Coming Soon
1. MDT Server installation/configuration
