## Gets list of available container templates based on user-input search string.
## Downloads chosen template to specified storage location in Proxmox VE using the pveam utility.
## Resources: https://pve.proxmox.com/pve-docs/pveam.1.html
##
## Created by: Alex B
## Date: July 22, 2024

## User inputs search string (ex: ubuntu)
read -p "Enter search string (ex: ubuntu, centos): " search_string

## Create list of available templates based on search_string
mapfile -t available_lxc_templates < <(pveam available | grep -i $search_string)
length=${#available_lxc_templates[@]}
## Holds list of matching template names
lxc_names=()
for ((i=0; i<$length; i++)); do
  IFS='        ' read -ra split_line <<< "${available_lxc_templates[$i]}"
  if [[ -n ${split_line[1]} ]]; then
  echo "Adding ${split_line[1]} to the list"
    lxc_names+=("${split_line[1]}")
  fi
done

## User selects the specific container template they want to download.
echo "These are the container templates that match your search:"
select lxc in "${lxc_names[@]}"; do
  echo "You selected: $lxc"
  break
done

## User chooses node (if there is only one node, it's auto-selected)
mapfile -t nodes < <(pvesh ls /nodes)
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

## Create list of available storage choices for the selected node
mapfile -t storage_list < <(pvesh get /nodes/$NODE_NAME/storage -content vztmpl -enabled --noborder --output json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
storage_names=()
for i in "${storage_list[@]}"; do

    ## Separates the number key, from the vnet information (the value)
    IFS='=' read -r key value <<< "$i"

    ## Use jq on the 'storage' object json string to extract the storage name.
    storage_name="$(jq -r '.storage' <<< "$value")"
    storage_names+=("$storage_name")
done

## User selects storage location for container template file
echo "Please select your storage location:"
select STORAGE_NAME in "${storage_names[@]}"; do
if [[ -n $STORAGE_NAME ]]; then
    echo -e "You have selected: \e[33m$STORAGE_NAME\e[0m"
    break
else
    echo "Invalid selection. Please try again."
fi
done

## Download the container template to specified storage location
pveam download $STORAGE_NAME $lxc