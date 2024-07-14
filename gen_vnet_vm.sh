#!/bin/bash
# 
# Script Name: create_vm.sh
# Description: This script creates a new VM in Proxmox.
# Author: Alex B.
# Date: 5/25/2024
# Version: 1.0
# Usage: Fill out necessary variables (VM/ISO STORAGE) then run: ./gen_vnet_vm.sh
# Please let me know if you think of a better name for the file.
#

## SDN Variables:
## source: https://stackoverflow.com/questions/38794449/creating-array-of-objects-in-bash
ZONE_NAME="testzone"
ZONE_COMMENT="This is a test zone."
VNET_NAME="testvnet"
VNET_ALIAS="testvnet"
VNET_SUBNET="10.0.0.0/24"
VNET_GATEWAY="10.0.0.1"

## ask user to enter VM_ID variable
echo -n "Please enter the VM ID: "
read VM_ID
# VM_ID=112


VM_NAME="lab-dc-01"

##
VM_STORAGE="" ## Where VM hard disk(s), TPM state, etc. are stored.
ISO_STORAGE="" ## script looks in this location to present menu of iso's

## FIREWALL Variables:
## Aliases that get used in firewall rules.
FIREWALL_RULES="dc-vm-rules.txt"
## Creates an alias for domain controller VM.
DC_ALIAS="labdc"
DC_COMMENT="Domain Controller"
DC_CIDR="10.0.0.2/32"
DC_REPLACEMENT_STR="((\$DC_ALIAS\$))"

## Creates an alias for domain/LAN.
LAN_ALIAS="lablan"
LAN_COMMENT="Domain LAN"
LAN_CIDR="10.0.0.1/24"
LAN_REPLACEMENT_STR="((\$LAN_ALIAS\$))"


## Get nodes / offer selection if more than one.
readarray -t nodes < <(pvesh ls /nodes)
length=${#nodes[@]}
echo $length
# filter findings so only filenames are listed in menu:
second_elements=()
# Split each line and add the second element to the array
for ((i=0; i<$length; i++)); do
  IFS='        ' read -ra split_line <<< "${nodes[$i]}"

  ## if split_line[1] is not empty, add it to the array.
  if [[ -n ${split_line[1]} ]]; then
    second_elements+=("${split_line[1]}")
  fi

  #second_elements+=("${split_line[1]}")
done
# Present the menu and get the user's choice
echo "Please select your node name, looks like the menu generation isn't perfect yet.."
select NODE_NAME in "${second_elements[@]}"; do
  if [[ -n $NODE_NAME ]]; then
    echo "You have selected: $NODE_NAME"
    break
  else
    echo "Invalid selection. Please try again."
  fi
done

## ISO / VM storage selection:
readarray -t storages < <(pvesh ls /nodes/$NODE_NAME/storage)
length=${#storages[@]}
echo $length
# filter findings so only filenames are listed in menu:
second_elements=()
# Split each line and add the second element to the array
for ((i=0; i<$length; i++)); do
  IFS='        ' read -ra split_line <<< "${storages[$i]}"

  ## if split_line[1] is not empty, add it to the array.
  if [[ -n ${split_line[1]} ]]; then
    second_elements+=("${split_line[1]}")
  fi

  #second_elements+=("${split_line[1]}")
done
# Present the menu and get the user's choice
echo "Please select storage that contains Windows and Virtio ISOs:"
select ISO_STORAGE in "${second_elements[@]}"; do
  if [[ -n $ISO_STORAGE ]]; then
    echo "You have selected: $ISO_STORAGE"
    break
  else
    echo "Invalid selection. Please try again."
  fi
done

# Present the menu and get the user's choice
echo "Please select storage to be used for VM hard disks:"
select VM_STORAGE in "${second_elements[@]}"; do
  if [[ -n $VM_STORAGE ]]; then
    echo "You have selected: $VM_STORAGE"
    break
  else
    echo "Invalid selection. Please try again."
  fi
done


echo "Creating zone: $ZONE_NAME"
pvesh create /cluster/sdn/zones --type simple --zone "$ZONE_NAME" --mtu 1460

echo "Creating vnet    : $VNET_NAME"
echo "Assigning subnet : $VNET_SUBNET"
echo "Assigning gateway: $VNET_GATEWAY"
pvesh create /cluster/sdn/vnets --vnet "$VNET_NAME" -alias "$VNET_ALIAS" -zone "$ZONE_NAME"
pvesh create /cluster/sdn/vnets/$VNET_NAME/subnets --subnet "$VNET_SUBNET" -gateway $VNET_GATEWAY -snat 0 -type subnet

echo "Applying SDN configuration."
pvesh set /cluster/sdn

## present menu of iso/file options to user from ISO_STORAGE disk.
readarray -t items_in_storage < <(pvesh ls /nodes/$NODE_NAME/storage/$ISO_STORAGE/content)
length=${#items_in_storage[@]}
echo $length
# filter findings so only filenames are listed in menu:
second_elements=()
# Split each line and add the second element to the array
for ((i=0; i<$length; i++)); do
  IFS='        ' read -ra split_line <<< "${items_in_storage[$i]}"
  second_elements+=("${split_line[1]}")
done
# Present the menu and get the user's choice
echo "Please select an iso to use for VM creation:"
select main_iso in "${second_elements[@]}"; do
  if [[ -n $main_iso ]]; then
    echo "You have selected: $main_iso"
    break
  else
    echo "Invalid selection. Please try again."
  fi
done

## assign a variable for virtio drivers:
echo "Please select the virtio driver iso."
select virtio_iso in "${second_elements[@]}"; do
  if [[ -n $virtio_iso ]]; then
    echo "You have selected: $virtio_iso"
    break
  else
    echo "Invalid selection. Please try again."
  fi
done


echo "Creating VM: $VM_NAME"

## create a vm using specified ISO.
## NEED TO MAKE SURE VM SEttings align with being able to create snapshots of VM.
## Seems to at least need to have image file be .qcow format (probably other factors as well)
pvesh create /nodes/$NODE_NAME/qemu -vmid $VM_ID -name "$VM_NAME" -storage $ISO_STORAGE \
      -memory 8192 -cpu cputype=x86-64-v2-AES -cores 2 -sockets 2 -cdrom "${main_iso}" \
      -ide1 "${virtio_iso},media=cdrom" -net0 virtio,bridge=$VNET_NAME \
      -scsihw virtio-scsi-pci -bios ovmf -machine pc-q35-8.1 -tpmstate "$VM_STORAGE:4,version=v2.0," \
      -efidisk0 "$VM_STORAGE:1" -bootdisk ide2 -ostype win11 \
      -agent 1 -virtio0 "$VM_STORAGE:32,iothread=1,format=qcow2" -boot "order=ide2;virtio0;scsi0"
      #-scsi0 "$VM_STORAGE:20,iothread=1,backup=1,snapshot=1" 
echo "Creating alias: $DC_ALIAS"

pvesh create /cluster/firewall/aliases --name "$DC_ALIAS" -comment "$DC_COMMENT" -cidr "$DC_CIDR"

echo "Replacing $DC_REPLACEMENT_STR with $DC_ALIAS in $FIREWALL_RULES."

while read -r line; do
  echo "${line//$DC_REPLACEMENT_STR/$DC_ALIAS}" >> /etc/pve/firewall/$VM_ID.fw.bak
done < $FIREWALL_RULES

echo "Creating alias: $LAN_ALIAS"

pvesh create /cluster/firewall/aliases --name "$LAN_ALIAS" -comment "$LAN_COMMENT" -cidr "$LAN_CIDR"

echo "Replacing $LAN_REPLACEMENT_STR with $LAN_ALIAS in $FIREWALL_RULES."

while read -r line; do
  echo "${line//$LAN_REPLACEMENT_STR/$LAN_ALIAS}" >> /etc/pve/firewall/$VM_ID.fw
done < /etc/pve/firewall/$VM_ID.fw.bak

echo "Removing backup file."

rm /etc/pve/firewall/$VM_ID.fw.bak