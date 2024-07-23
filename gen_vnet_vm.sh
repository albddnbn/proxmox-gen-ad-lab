#!/bin/bash
# Script Name: gen_vnet_vm.sh
# Author: Alex B.
# Date: 7/13/2024
# Description: create a new VM in Proxmox. Used to create a domain controller / Windows Server VM, or client Windows 10 VMs.

## If values are not set - script will prompt user for values during execution.
declare -A VARS=(
  ## Virtual networking:
  ["ZONE_NAME"]="zone3"                     # Ex: testzone
  ["ZONE_COMMENT"]="AD Test zone3"                  # Ex: This is a test zone comment.
  ["VNET_NAME"]="vnet3"                     # Ex: testvnet
  ["VNET_ALIAS"]="vnet3zone3"                    # Ex: testvnet
  ["VNET_SUBNET"]="10.0.22.0/24"                   # Ex: 10.0.0.0/24
  ["VNET_GATEWAY"]="10.0.22.1"                  # Ex: 10.0.0.1

  ## Details for VM creation:
  ["VM_ID"]="222"                         # Ex: 101
  ["VM_NAME"]="test-dc-3"                       # Ex: lab-dc-01
  ["FIREWALL_RULES_FILE"]="dc-vm-rules.txt"

  ## 'Aliases' used for firewall rules/elsewhere in Proxmox OS
  ["DC_ALIAS"]="testdc3"                      # Ex: labdc
  ["DC_COMMENT"]="Domain controller"   # Ex: Domain Controller
  ["DC_CIDR"]="10.0.22.2/32"                       # Ex: 10.0.0.2/32
  ## Used to replace string with dc_alias in firewall rules file:
  ["DC_REPLACEMENT_STR"]="((\$DC_ALIAS\$))"

  ["LAN_ALIAS"]="dc3lan"                     # Ex: lablan
  ["LAN_COMMENT"]="Domain LAN"         # Ex: Domain LAN
  ["LAN_CIDR"]="10.0.22.1/24"                      # Ex: 10.0.0.1/24
  ## Used to replace string with lan_alias in firewall rules file:
  ["LAN_REPLACEMENT_STR"]="((\$LAN_ALIAS\$))"
  ["VM_HARDDISK_SIZE"]="60"                    # Ex: 60 would create a 60 GB hard disk.
)

## The user is prompted for two storage disk choices.
## ISO_STORAGE = where Windows and VirtIO ISOs are stored.
## VM_STORAGE = where the VM's hard disk(s), TPM, etc. will be stored.
declare -A STORAGE_OPTIONS=(
  ["ISO_STORAGE"]="Please select storage that contains \e[33mWindows and Virtio ISOs:\e[0m"
  ["VM_STORAGE"]="Please select storage to be used for \e[33mVM hard disks:\e[0m"
)

## The user is prompted to select the Windows and VirtIO isos, from the contents of STORAGE_OPTIONS['ISO_STORAGE'].
declare -A chosen_isos=(
  ["main_iso"]="Please select \e[33moperating system ISO:\e[0m"
  ["virtio_iso"]="Please select \e[33mVirtIO / Secondary ISO:\e[0m"
)

## Loop through the VARS array, prompt user for any missing values.
for var in "${!VARS[@]}"; do
  if [[ -z "${VARS[$var]}" ]]; then
    read -p "Enter a value for ${var}: " value
    ## Strip whitespace from value, if it exists.
    ## if var doesn't end with _COMMENT, strip whitespace from value.
    if [[ $var != *_COMMENT ]]; then
    VARS[$var]="$(echo -e "${value}" | tr -d '[:space:]')"
    else
    VARS[$var]="${value:-}"
    fi
  fi
done

# Print variables/values to terminal for clarification
echo -e "\e[33mVirtual networking details:\e[0m"
echo "ZONE_NAME:     ${VARS[ZONE_NAME]}"
echo "ZONE_COMMENT:  ${VARS[ZONE_COMMENT]}"
echo "VNET_NAME:     ${VARS[VNET_NAME]}"
echo "VNET_ALIAS:    ${VARS[VNET_ALIAS]}"
echo "VNET_SUBNET:   ${VARS[VNET_SUBNET]}"
echo "VNET_GATEWAY:  ${VARS[VNET_GATEWAY]}"
echo ""
echo -e "\e[33mVirtual machine:\e[0m"
echo "VM_ID:         ${VARS[VM_ID]}"
echo "VM_NAME:       ${VARS[VM_NAME]}"
echo "FIREWALL_RULES_FILE: ${VARS[FIREWALL_RULES_FILE]}"
echo ""
echo -e "\e[33mAliases and other info for firewall rules:\e[0m"
echo "DC_ALIAS:      ${VARS[DC_ALIAS]}"
echo "DC_COMMENT:    ${VARS[DC_COMMENT]}"
echo "DC_CIDR:       ${VARS[DC_CIDR]}"
echo "DC_REPLACEMENT_STR: ${VARS[DC_REPLACEMENT_STR]}"
echo ""
echo "LAN_ALIAS:     ${VARS[LAN_ALIAS]}"
echo "LAN_COMMENT:   ${VARS[LAN_COMMENT]}"
echo "LAN_CIDR:      ${VARS[LAN_CIDR]}"
echo "LAN_REPLACEMENT_STR: ${VARS[LAN_REPLACEMENT_STR]}"

## Node selection - if multiple nodes are present, user is prompted to choose one.
readarray -t nodes < <(pvesh ls /nodes)
length=${#nodes[@]}
if [[ $length -gt 1 ]]; then
  echo "\e[33mMultiple nodes found:\e[0m Please select the node you would like to use."
  filename_strings=()
  for ((i=0; i<$length; i++)); do
    IFS='        ' read -ra split_line <<< "${nodes[$i]}"
    filename_strings+=("${split_line[1]}")
  done
  echo "Please select your node name:"
  select NODE_NAME in "${filename_strings[@]}"; do
    if [[ -n $NODE_NAME ]]; then
      echo -e "You have selected: \e[33m$NODE_NAME\e[0m"
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
else
  IFS='        ' read -ra split_line <<< "${nodes[0]}"
  NODE_NAME="${split_line[1]}"
  echo -e "\nAuto-selected node: \e[33m$NODE_NAME\e[0m"
fi

## User is presented with two more menus.
## Menu 1 = ISO_STORAGE; this storage drive should contain your Windows and VirtIO ISOs
## Menu 2 = VM_STORAGE; this storage drive will contain the VM's hard disk(s), TPM state, etc.

# List is created from all storages available on node:
readarray -t storages < <(pvesh ls /nodes/$NODE_NAME/storage)
length=${#storages[@]}
# filter findings so only filenames are listed in menu:
filename_strings=()
# Split each line and add the second element to the array
for ((i=0; i<$length; i++)); do
  IFS='        ' read -ra split_line <<< "${storages[$i]}"
  ## if split_line[1] is not empty, add it to the array.
  if [[ -n ${split_line[1]} ]]; then
    filename_strings+=("${split_line[1]}")
  fi
done

## Prompt user for STORAGE_OPTIONS values
for var in "${!STORAGE_OPTIONS[@]}"; do
  echo -e "\n${STORAGE_OPTIONS[$var]}"
  select STORAGE_OPTION in "${filename_strings[@]}"; do
    if [[ -n $STORAGE_OPTION ]]; then
      echo -e "Disk selected: \e[33m$STORAGE_OPTION\e[0m\n"
      STORAGE_OPTIONS[$var]=$STORAGE_OPTION
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
done;

## Virtual Network Creation:
## ZONE
echo -e "Creating zone: \e[36m${VARS['ZONE_NAME']}\e[0m"
pvesh create /cluster/sdn/zones --type simple --zone "${VARS['ZONE_NAME']}" --mtu 1460
## VNET w/SUBNET
echo "Creating vnet    : ${VARS['VNET_NAME']}"
echo "Assigning subnet : ${VARS['VNET_SUBNET']}"
echo "Assigning gateway: ${VARS['VNET_GATEWAY']}"
pvesh create /cluster/sdn/vnets --vnet "${VARS['VNET_NAME']}" -alias "${VARS['VNET_ALIAS']}" -zone "${VARS['ZONE_NAME']}"
pvesh create /cluster/sdn/vnets/${VARS['VNET_NAME']}/subnets --subnet "${VARS['VNET_SUBNET']}" -gateway ${VARS['VNET_GATEWAY']} -snat 0 -type subnet

echo "Applying SDN configuration."
pvesh set /cluster/sdn

## Creates array of items/files found on STORAGE_OPTIONS['ISO_STORAGE'] drive:
readarray -t items_in_storage < <(pvesh ls /nodes/$NODE_NAME/storage/${STORAGE_OPTIONS['ISO_STORAGE']}/content)
length=${#items_in_storage[@]}
filename_strings=()
# Split each line and add the second element to the array
for ((i=0; i<$length; i++)); do
  IFS='        ' read -ra split_line <<< "${items_in_storage[$i]}"
  filename_strings+=("${split_line[1]}")
done

## User is prompted to select Windows and VirtIO isos
for var in "${!chosen_isos[@]}"; do
  echo -e "\n${chosen_isos[$var]}"
  select STORED_ISO in "${filename_strings[@]}"; do
    if [[ -n $STORED_ISO ]]; then
      echo -e "\nYou have selected: \e[33m$STORED_ISO\e[0m"
      chosen_isos[$var]=$STORED_ISO
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
done;

echo -e "\nCreating VM: \e[36m${VARS['VM_NAME']}\e[0m\n"

## Creates a vm using specified ISO(s) and storage locations.
# Reference for 'ideal' VM settings: https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
pvesh create /nodes/$NODE_NAME/qemu -vmid ${VARS['VM_ID']} -name "${VARS['VM_NAME']}" -storage ${STORAGE_OPTIONS['ISO_STORAGE']} \
      -memory 8192 -cpu cputype=x86-64-v2-AES -cores 2 -sockets 2 -cdrom "${chosen_isos['main_iso']}" \
      -ide1 "${chosen_isos['virtio_iso']},media=cdrom" -net0 "virtio,bridge=${VARS['VNET_NAME']},firewall=1" \
      -scsihw virtio-scsi-pci -bios ovmf -machine pc-q35-8.1 -tpmstate "${STORAGE_OPTIONS['VM_STORAGE']}:4,version=v2.0," \
      -efidisk0 "${STORAGE_OPTIONS['VM_STORAGE']}:1" -bootdisk ide2 -ostype win11 \
      -agent 1 -virtio0 "${STORAGE_OPTIONS['VM_STORAGE']}:${VARS['VM_HARDDISK_SIZE']},iothread=1,format=qcow2" -boot "order=ide2;virtio0;scsi0"
      #-scsi0 "$VM_STORAGE:20,iothread=1,backup=1,snapshot=1"

## FIREWALL RULES FOR VM (/etc/pve/firewall)
## Alias is created at the datacenter level for domain controller VM
echo "Creating alias: ${VARS['DC_ALIAS']}"

pvesh create /cluster/firewall/aliases --name "${VARS['DC_ALIAS']}" -comment "${VARS['DC_COMMENT']}" -cidr "${VARS['DC_CIDR']}"

echo "Replacing ${VARS['DC_REPLACEMENT_STR']} with ${VARS['DC_ALIAS']} in ${VARS['FIREWALL_RULES_FILE']}."

## Using the original firewall rules file, a new firewall rules file is generated in /etc/pve/firewall/ directory
## using the VMs ID number and inserting the domain controller's alias. .bak is appended to filename.
while read -r line; do
  echo "${line//${VARS['DC_REPLACEMENT_STR']}/${VARS['DC_ALIAS']}}" >> /etc/pve/firewall/${VARS['VM_ID']}.fw.bak
done < "${VARS['FIREWALL_RULES_FILE']}"

## Alias is created at the datacenter for the Domain/LAN network:
echo "Creating alias: ${VARS['LAN_ALIAS']}"

pvesh create /cluster/firewall/aliases --name "${VARS['LAN_ALIAS']}" -comment "${VARS['LAN_COMMENT']}" -cidr "${VARS['LAN_CIDR']}"

echo "Replacing ${VARS['LAN_REPLACEMENT_STR']} with ${VARS['LAN_ALIAS']} in ${VARS['FIREWALL_RULES_FILE']}."

## Using the backup file created earlier, the LAN alias is inserted into the firewall rules file.
while read -r line; do
  echo "${line//${VARS['LAN_REPLACEMENT_STR']}/${VARS['LAN_ALIAS']}}" >> /etc/pve/firewall/${VARS['VM_ID']}.fw
done < /etc/pve/firewall/${VARS['VM_ID']}.fw.bak

echo "Removing backup file."
rm /etc/pve/firewall/${VARS['VM_ID']}.fw.bak
