#!/bin/bash
## Script will remove specified zone, and all of it's vnet/subnet children in Proxmox VE using Proxmox API.
## Created by Alex B. / July 21, 2024

apt install jq -y

## Creates a list of all Zones in the Proxmox cluster
readarray -t zones_list < <(pvesh ls /cluster/sdn/zones)
length=${#zones_list[@]}
zone_names_list=()
# Split each line and add the second element to the array
for ((i=0; i<$length; i++)); do
    IFS='        ' read -ra split_line <<< "${zones_list[$i]}"
    zone_names_list+=("${split_line[1]}")
done

## Use the zone list to present menu to user - user selects zone they want to completely remove
echo -e "\nPlease select the \e[33mzone you'd like to remove:\e[0m"
    select ZONE_CHOICE in "${zone_names_list[@]}"; do
    if [[ -n $ZONE_CHOICE ]]; then
        echo -e "Zone selected: \e[33m$ZONE_CHOICE\e[0m\n"
        ZONE_CHOICE[$var]=$ZONE_CHOICE
        break
    else
        echo "Invalid selection. Please try again."
    fi
done;


## Creates an array of listings from the vnet API endpoint
readarray -t vnets_json_string < <(pvesh get /cluster/sdn/vnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
## You basically end up with a numbered list, vnets_json_string[0] being the first vnet  and related information
for i in "${vnets_json_string[@]}"; do

    ## Separates the number key, from the vnet information (the value)
    IFS='=' read -r key value <<< "$i"

    ## Use jq tool to extract value for vnet and zone name
    current_vnet="$(jq -r '.vnet' <<< "$value")"
    current_vnet_zone_name="$(jq -r '.zone' <<< "$value")"
    #echo "current_vnet: $current_vnet"

    ## If current vnet in cycle's zone matches zone choice - delete the vnet and all of it's subnets.
    if [[ $current_vnet_zone_name == $ZONE_CHOICE ]]; then

        ## Get listing of subnets, take same approach
        readarray -t subnets_json_string < <(pvesh get /cluster/sdn/vnets/$current_vnet/subnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
        for i in "${subnets_json_string[@]}"; do
            IFS='=' read -r key value <<< "$i"
            current_subnet="$(jq -r '.subnet' <<< "$value")"
            echo "current_subnet: $current_subnet"
            pvesh delete /cluster/sdn/vnets/$current_vnet/subnets/$current_subnet
        done

        ## delete the vnet
        pvesh delete /cluster/sdn/vnets/$current_vnet

    fi
done

## Delete the zone:
pvesh delete /cluster/sdn/zones/$ZONE_CHOICE

## Reload networking config:
pvesh set /cluster/sdn
