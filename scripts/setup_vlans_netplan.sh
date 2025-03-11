#!/bin/bash

# Help function
Help()
{
    echo "Script help prompt"
    echo
    echo "Usage:"
    echo "sudo ./setup_vlans_netplan.sh -i interface -n hostID"
    echo
    echo "Example:"
    echo "sudo ./setup_vlans_netplan.sh -i eno1 -n 2"
    echo
}

# Get options
while getopts ":hi:n:" option; do
    case $option in
        h) # Display Help
            Help
            exit;;
        i) # Define main interface
            MAIN_IF=$OPTARG;;
        n) # Define host ID
            HOST_ID=$OPTARG;;
        \?) # Invalid option
            echo "Error: Invalid option"
            Help
            exit 1;;
    esac
done

# Validate required parameters
if [[ -z "$MAIN_IF" || -z "$HOST_ID" ]]; then
    echo "Error: Both -i (interface) and -n (host ID) options are required."
    Help
    exit 1
fi

# Set hostname
sudo hostnamectl set-hostname "saci-0$HOST_ID"

# Disable cloud-init network management
CLOUD_CFG="/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
echo "Disabling cloud-init network management..."
sudo mkdir -p "$(dirname "$CLOUD_CFG")"
echo "network: {config: disabled}" | sudo tee "$CLOUD_CFG"

# Define Netplan config file
NETPLAN_FILE="/etc/netplan/01-vlan-setup.yaml"

# Static IP addresses for each VLAN
declare -A VLAN_IPS=(
    [100]="10.0.10.$HOST_ID/24"
    [200]="10.0.20.$HOST_ID/24"
    [300]="10.0.30.$HOST_ID/24"
    [500]="10.0.50.$HOST_ID/24"
)

# Define VLANs and their corresponding bridge names
declare -A VLAN_BRIDGES=(
    [100]="br_ran"
    [200]="br_core"
    [300]="br_sec"
    [500]="br_storage"
)

# Main (native VLAN 400) bridge name
MAIN_BRIDGE="br_main"

# Start writing the Netplan YAML
cat <<EOF | sudo tee "$NETPLAN_FILE"
network:
    version: 2
    ethernets:
        $MAIN_IF:
            dhcp4: no
            dhcp6: no
    vlans:
EOF

# Add VLAN interfaces
for VLAN_ID in "${!VLAN_BRIDGES[@]}"; do
    VLAN_IF="vlan$VLAN_ID"

    cat <<EOF | sudo tee -a "$NETPLAN_FILE"
        $VLAN_IF:
            id: $VLAN_ID
            link: $MAIN_IF
            dhcp4: no
EOF
done

# Add bridges section
cat <<EOF | sudo tee -a "$NETPLAN_FILE"
    bridges:
        $MAIN_BRIDGE:
            interfaces: [$MAIN_IF]
            dhcp4: true
            dhcp4-overrides:
                send-hostname: true
                hostname: $HOSTNAME
            nameservers:
                addresses: [10.127.65.11, 10.127.72.11]
EOF

# Add bridges for VLANs
for VLAN_ID in "${!VLAN_BRIDGES[@]}"; do
    VLAN_IF="vlan$VLAN_ID"
    BR_IF="${VLAN_BRIDGES[$VLAN_ID]}"
    IP="${VLAN_IPS[$VLAN_ID]}"

    cat <<EOF | sudo tee -a "$NETPLAN_FILE"
        $BR_IF:
            interfaces: [$VLAN_IF]
            dhcp4: no
            addresses: [$IP]
EOF
done

# Apply Netplan configuration
echo "Applying Netplan configuration..."
sudo netplan generate
sudo netplan apply

echo "VLAN and bridge setup applied via Netplan."
