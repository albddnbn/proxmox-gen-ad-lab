#!/bin/bash
# Script Name: gen_vnet_vm.sh
# Author: Alex B.
# Date: 7/13/2024
# Description: create a new VM in Proxmox. Used to create a domain controller / Windows Server VM, or client Windows 10 VMs.

## If key values are not set - script will prompt user for values during execution.
declare -A VARS=(
  ## Virtual networking:
  ["ZONE_NAME"]=""    # Ex: testzone
  ["ZONE_COMMENT"]="" # Ex: This is a test zone comment.
  ["VNET_NAME"]=""    # Ex: testvnet
  ["VNET_ALIAS"]=""   # Ex: testvnet
  ["VNET_SUBNET"]=""  # Ex: 10.0.0.0/24
  ["VNET_GATEWAY"]="" # Ex: 10.0.0.1

  ## Details for VM creation:
  ["VM_ID"]=""        # Ex: 101
  ["VM_NAME"]=""      # Ex: lab-dc-01
  ["FIREWALL_RULES_FILE"]="dc-vm-rules.txt"

  ## 'Aliases' used for firewall rules/elsewhere in Proxmox OS
  ["DC_ALIAS"]=""     # Ex: labdc
  ["DC_COMMENT"]="Domain controller"   # Ex: Domain Controller
  ["DC_CIDR"]=""      # Ex: 10.0.0.2/32
  ## Used to replace string with dc_alias in firewall rules file:
  ["DC_REPLACEMENT_STR"]="((\$DC_ALIAS\$))"

  ["LAN_ALIAS"]=""    # Ex: lablan
  ["LAN_COMMENT"]="Domain LAN"  # Ex: Domain LAN
  ["LAN_CIDR"]=""     # Ex: 10.0.0.1/24
  ## Used to replace string with lan_alias in firewall rules file:
  ["LAN_REPLACEMENT_STR"]="((\$LAN_ALIAS\$))"
)

# Loop through the VARS associative array - if any key does not have a value, user is prompted to enter it.
for var in "${!VARS[@]}"; do
  if [[ -z "${VARS[$var]}" ]]; then
    read -p "Enter a value for ${var}: " value
    VARS[$var]="${value:-}"
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

## Proxmox node selection - a menu is presented if > 1 node is discovered.
readarray -t nodes < <(pvesh ls /nodes)
length=${#nodes[@]}
if [[ $length -gt 1 ]]; then
  echo "Multiple nodes found. Please select the node you would like to use."
  filename_strings=()
  for ((i=0; i<$length; i++)); do
    IFS='        ' read -ra split_line <<< "${nodes[$i]}"
    filename_strings+=("${split_line[1]}")
  done
  echo "Please select your node name:"
  select NODE_NAME in "${filename_strings[@]}"; do
    if [[ -n $NODE_NAME ]]; then
      echo "You have selected: $NODE_NAME"
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
else
  IFS='        ' read -ra split_line <<< "${nodes[0]}"
  NODE_NAME="${split_line[1]}"
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

## User is almost assuredly prompted for storage paths using a menu system.
declare -A STORAGE_OPTIONS=(
  ["ISO_STORAGE"]="Please select storage that contains Windows and Virtio ISOs:"
  ["VM_STORAGE"]="Please select storage to be used for VM hard disks:"
)

for var in "${!STORAGE_OPTIONS[@]}"; do
  echo "${STORAGE_OPTIONS[$var]}"
  select STORAGE_OPTION in "${filename_strings[@]}"; do
    if [[ -n $STORAGE_OPTION ]]; then
      echo "You have selected: $STORAGE_OPTION"
      STORAGE_OPTIONS[$var]=$STORAGE_OPTION
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
done;

echo -e "Creating zone: \e[36m${VARS['ZONE_NAME']}\e[0m"
pvesh create /cluster/sdn/zones --type simple --zone "${VARS['ZONE_NAME']}" --mtu 1460

echo "Creating vnet    : ${VARS['VNET_NAME']}"
echo "Assigning subnet : ${VARS['VNET_SUBNET']}"
echo "Assigning gateway: ${VARS['VNET_GATEWAY']}"
## Proxmox API
pvesh create /cluster/sdn/vnets --vnet "${VARS['VNET_NAME']}" -alias "$VNET_ALIAS" -zone "${VARS['ZONE_NAME']}"
pvesh create /cluster/sdn/vnets/${VARS['VNET_NAME']}/subnets --subnet "${VARS['VNET_SUBNET']}" -gateway ${VARS['VNET_GATEWAY']} -snat 0 -type subnet

echo "Applying SDN configuration."
pvesh set /cluster/sdn


## Using the chosen iso_storage option - present menus to user so they can choose the actual ISOs that will be attached
## to the new VM:

declare -A chosen_isos=(
  ["main_iso"]="Please select operating system ISO:"
  ["virtio_iso"]="Please select VirtIO / Secondary ISO:"
)

#echo "/nodes/$NODE_NAME/storage/${STORAGE_OPTIONS['ISO_STORAGE']}/content"
## Creates a list of available optoins that will be presented in menu.
readarray -t items_in_storage < <(pvesh ls /nodes/$NODE_NAME/storage/${STORAGE_OPTIONS['ISO_STORAGE']}/content)
length=${#items_in_storage[@]}
filename_strings=()
# Split each line and add the second element to the array
for ((i=0; i<$length; i++)); do
  IFS='        ' read -ra split_line <<< "${items_in_storage[$i]}"
  filename_strings+=("${split_line[1]}")
done


for var in "${!chosen_isos[@]}"; do
  echo "${chosen_isos[$var]}"
  select STORED_ISO in "${filename_strings[@]}"; do
    if [[ -n $STORED_ISO ]]; then
      echo "You have selected: $STORED_ISO"
      chosen_isos[$var]=$STORED_ISO
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
done;

echo -e "Creating VM: \e[36m${VARS['VM_NAME']}\e[0m"

## Creates a vm using specified ISO(s) and storage locations.
# Reference for 'ideal' VM settings: https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
pvesh create /nodes/$NODE_NAME/qemu -vmid ${VARS['VM_ID']} -name "${VARS['VM_NAME']}" -storage ${STORAGE_OPTIONS['ISO_STORAGE']} \
      -memory 8192 -cpu cputype=x86-64-v2-AES -cores 2 -sockets 2 -cdrom "${chosen_isos['main_iso']}" \
      -ide1 "${chosen_isos['virtio_iso']},media=cdrom" -net0 virtio,bridge=${VARS['VNET_NAME']} \
      -scsihw virtio-scsi-pci -bios ovmf -machine pc-q35-8.1 -tpmstate "${STORAGE_OPTIONS['VM_STORAGE']}:4,version=v2.0," \
      -efidisk0 "${STORAGE_OPTIONS['VM_STORAGE']}:1" -bootdisk ide2 -ostype win11 \
      -agent 1 -virtio0 "${STORAGE_OPTIONS['VM_STORAGE']}:32,iothread=1,format=qcow2" -boot "order=ide2;virtio0;scsi0"
      #-scsi0 "$VM_STORAGE:20,iothread=1,backup=1,snapshot=1"

## Creation of Aliases / firewall rules / etc.
echo "Creating alias: ${VARS['DC_ALIAS']}"

pvesh create /cluster/firewall/aliases --name "${VARS['DC_ALIAS']}" -comment "${VARS['DC_COMMENT']}" -cidr "${VARS['DC_CIDR']}"

echo "Replacing ${VARS['DC_REPLACEMENT_STR']} with ${VARS['DC_ALIAS']} in ${VARS['FIREWALL_RULES_FILE']}."

while read -r line; do
  echo "${line//${VARS['DC_REPLACEMENT_STR']}/${VARS['DC_ALIAS']}}" >> /etc/pve/firewall/${VARS['VM_ID']}.fw.bak
done < "${VARS['FIREWALL_RULES_FILE']}"

echo "Creating alias: ${VARS['LAN_ALIAS']}"

pvesh create /cluster/firewall/aliases --name "${VARS['LAN_ALIAS']}" -comment "${VARS['LAN_COMMENT']}" -cidr "${VARS['LAN_CIDR']}"

echo "Replacing ${VARS['LAN_REPLACEMENT_STR']} with ${VARS['LAN_ALIAS']} in ${VARS['FIREWALL_RULES_FILE']}."

while read -r line; do
  echo "${line//${VARS['LAN_REPLACEMENT_STR']}/${VARS['LAN_ALIAS']}}" >> /etc/pve/firewall/${VARS['VM_ID']}.fw
done < /etc/pve/firewall/${VARS['VM_ID']}.fw.bak

echo "Removing backup file."

rm /etc/pve/firewall/${VARS['VM_ID']}.fw.bak
