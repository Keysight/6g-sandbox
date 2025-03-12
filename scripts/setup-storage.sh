#!/bin/bash

# General Variables
CEPH_CLUSTER_NETWORK="10.0.50.0/24"
CEPH_PUBLIC_NETWORK="10.0.50.0/24"

# Verify arguments
if [[ -z "$1" ]]; then
    echo "Usage: $0 <disk_or_partition>"
    echo "Examples: $0 /dev/sdb or $0 /dev/sdb1"
    exit 1
fi

STORAGE_DEVICE="$1"

# Add Ceph repository (Debian/Ubuntu)
cat <<EOF > /etc/apt/sources.list.d/ceph.list
deb https://download.ceph.com/debian-quincy/ $(lsb_release -cs) main
EOF

# Import GPG key
curl -fsSL https://download.ceph.com/keys/release.asc | gpg --dearmor -o /usr/share/keyrings/ceph-release-keyring.gpg
apt update

# Install Ceph packages
apt install -y ceph ceph-common ceph-fuse ceph-volume ceph-deploy

# Initialize Ceph cluster on saci-01 (manager node)
if [[ "$(hostname)" == "saci-01" ]]; then
    echo "✅ Initializing Ceph MON and MGR on saci-01"
    mkdir ~/ceph-cluster
    cd ~/ceph-cluster
    ceph-deploy new saci-01

    # Configure networks
    echo "public network = $CEPH_PUBLIC_NETWORK" >> ceph.conf
    echo "cluster network = $CEPH_CLUSTER_NETWORK" >> ceph.conf

    # Create initial MON and MGR services
    ceph-deploy mon create-initial
    ceph-deploy mgr create saci-01

    # Distribute admin keys
    ceph-deploy admin saci-01
    chmod +r /etc/ceph/ceph.client.admin.keyring
fi

# Create OSD on each host
echo "✅ Creating OSD on $(hostname)"

# Wipe the storage device before use
ceph-volume lvm zap $STORAGE_DEVICE

# Create OSD on the given device
ceph-volume lvm create --data $STORAGE_DEVICE

# Register OSD from saci-01 (execute after all nodes have run their scripts)
if [[ "$(hostname)" == "saci-01" ]]; then
    cd ~/ceph-cluster
    for node in saci-02 saci-03 saci-04 saci-05 saci-06 saci-07 saci-08 saci-09 saci-10; do
        ceph-deploy admin $node
        ssh $node 'chmod +r /etc/ceph/ceph.client.admin.keyring'
    done
fi

echo "✅ Deployment completed on $(hostname)."
