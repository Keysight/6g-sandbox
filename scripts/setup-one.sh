#!/bin/bash

# Help function
Help()
{
    echo "Script help prompt"
    echo
    echo "Usage:"
    echo "sudo ./setup-one.sh -p password"
    echo
    echo "Example:"
    echo "sudo ./setup-one.sh -p mypassword"
    echo
}

# Get options
while getopts ":hp:" option; do
   case $option in
      h) # display Help
         Help
         exit;;
      p) # Define the oneadmin password
         ONE_PSWD=$OPTARG;;
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done

# Validate options
if [[ -z "$ONE_PSWD" ]]; then
    echo "Error: Password option is required."
    Help
    exit 1
fi

# === CONFIGURATION ===
FRONTEND_IP="10.0.50.1"        # IP del OpenNebula Frontend (host 01)
COMPUTE_NODE_IP=$(hostname -I | awk '{print $5}')  # Detecta la IP del nodo
OPENNEBULA_VERSION="6.10"

echo "✅ Step 1: Adding OpenNebula Repositories..."

# Import the repository key
wget -q -O- https://downloads.opennebula.io/repo/repo2.key | gpg --dearmor --yes --output /etc/apt/keyrings/opennebula.gpg

# Add the repository for Debian/Ubuntu
echo "deb [signed-by=/etc/apt/keyrings/opennebula.gpg] https://downloads.opennebula.io/repo/6.10/Ubuntu/24.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list

# Update repo list
apt update

echo "✅ Step 2: Installing OpenNebula Node packages..."
apt update
apt install -y opennebula-node qemu-system libvirt-daemon-system libvirt-clients

echo "✅ Step 3: Configuring Libvirt for OpenNebula..."
systemctl enable libvirtd
systemctl start libvirtd

echo "✅ Step 4: Configuring SSH access for OpenNebula Frontend..."

# Asegurar que hay clave SSH en el Frontend (esto debería hacerlo una vez desde el Frontend)
echo "oneadmin:$ONE_PSWD" | chpasswd
ssh-keyscan $FRONTEND_IP >> ~/.ssh/known_hosts

echo "⚠️ Please make sure that the OpenNebula Frontend has already copied its SSH key to this compute node."
echo "⚠️ Example (on the Frontend): ssh-copy-id root@$COMPUTE_NODE_IP"
read -p "Press Enter to continue after confirming SSH works without password..."

echo "✅ All done! Check Sunstone to verify the host is visible."
