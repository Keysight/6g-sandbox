#!/bin/bash

# Help function
Help()
{
    echo "Script help prompt"
    echo
    echo "Usage:"
    echo "sudo ./setup_vlans.sh -i interface -n hostID"
    echo
    echo "Example:"
    echo "sudo ./setup_vlans.sh -i eno1 -n 2"
    echo
}

# Get options
while getopts ":hi:n:" option; do
   case $option in
      h) # display Help
         Help
         exit;;
      i) # Define the main interface
         MAIN_IF=$OPTARG;;
      n) # Define the host ID
         HOST_ID=$OPTARG;;
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done

# Validate options
if [[ -z "$MAIN_IF" || -z "$HOST_ID" ]]; then
    echo "Error: Both -i (interface) and -n (host ID) options are required."
    Help
    exit 1
fi

# Define VLANs and their corresponding IP addresses
declare -A VLAN_IPS=(
    [100]="10.0.10.$HOST_ID/24"
    [200]="10.0.20.$HOST_ID/24"
    [300]="10.0.30.$HOST_ID/24"
    [500]="10.0.50.$HOST_ID/24"
    #[600]="10.0.60.$HOST_ID/24"
)

# Define VLANs and their corresponding bridge names
declare -A VLAN_BRIDGES=(
    [100]="br_ran"
    [200]="br_core"
    [300]="br_sec"
    [500]="br_storage"
    #[600]="br_infra"
)

# Define the bridge for the main (native VLAN) interface
MAIN_BRIDGE="br_main"
#INT_IP_ADDR="10.0.40.$HOST_ID/24"

# Setup hostname
hostnamectl set-hostname "saci-0$HOST_ID"

# Load VLAN module if not already loaded
if ! lsmod | grep -q 8021q; then
    echo "Loading 8021q module..."
    sudo modprobe 8021q
fi

### **1 Setup VLANs with Bridges**
for VLAN_ID in "${!VLAN_IPS[@]}"; do
    VLAN_IF="vlan$VLAN_ID"
    BR_IF="${VLAN_BRIDGES[$VLAN_ID]}"  # Get the custom bridge name

    echo "Creating VLAN $VLAN_ID on $MAIN_IF as $VLAN_IF..."
    sudo ip link add link "$MAIN_IF" name "$VLAN_IF" type vlan id "$VLAN_ID"

    echo "Creating bridge $BR_IF for VLAN $VLAN_ID..."
    sudo ip link add name "$BR_IF" type bridge

    echo "Adding $VLAN_IF to bridge $BR_IF..."
    sudo ip link set "$VLAN_IF" master "$BR_IF"

    echo "Assigning IP ${VLAN_IPS[$VLAN_ID]} to bridge $BR_IF..."
    sudo ip addr add "${VLAN_IPS[$VLAN_ID]}" dev "$BR_IF"

    echo "Bringing up interfaces $VLAN_IF and $BR_IF..."
    sudo ip link set "$VLAN_IF" up
    sudo ip link set "$BR_IF" up
done

echo "Bringing up $MAIN_BRIDGE and $MAIN_IF..."
sudo ip link set "$MAIN_IF" up

### **2 Setup Main Interface Bridge**
echo "Creating bridge $MAIN_BRIDGE for the main (native VLAN) interface..."
sudo ip link add name "$MAIN_BRIDGE" type bridge

#echo "Assigning IP $INT_IP_ADDR to $MAIN_BRIDGE..."
#sudo ip addr add "$INT_IP_ADDR" dev "$MAIN_BRIDGE"

### **3 Configure DHCP on VLAN 400**
echo -e "[Match]\nName=br_main\n\n[Network]\nDHCP=ipv4" | sudo tee /etc/systemd/network/br_main.network
sudo systemctl restart systemd-networkd
sudo resolvectl dns br_main 10.127.65.11 10.127.72.11



echo "Adding $MAIN_IF to $MAIN_BRIDGE..."
sudo ip link set "$MAIN_IF" master "$MAIN_BRIDGE"
sudo ip link set "$MAIN_BRIDGE" up

echo "VLAN and bridge setup complete!"
ip -d link show | grep vlan
ip -d link show | grep br
