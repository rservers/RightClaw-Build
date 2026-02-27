#!/bin/bash
# ============================================================
# RIGHT SERVERS — AutoVM Setup Script for Rightclaw Template
# 
# INSTALL: AutoVM Admin > Template > Script > Create
#   Name:             Rightclaw Setup
#   Template:         rightservers-openclaw-base-v1
#   Type:             Setup
#   Where is program: /bin/bash
#   Where to upload:  /home/setup.sh
#   How to execute:   /home/setup.sh
# ============================================================

# --- Network Interface ---
interface=$(ls /sys/class/net | grep -v lo | head -n 1)

# --- Netmask to CIDR ---
cat <<'EOF' > /etc/cidr.py
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('netmask')
args = parser.parse_args()
cidr = sum(bin(int(b)).count('1') for b in args.netmask.split('.'))
print(cidr)
EOF

if which python3; then
    cidr=$(python3 /etc/cidr.py @netmask)
else
    cidr=$(python /etc/cidr.py @netmask)
fi

# --- Network Configuration (Netplan) ---
if [ "$cidr" == "32" ]; then
    # Point-to-point /32 route
    cat <<EOF > /etc/netplan/config.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      addresses: [@address/$cidr]
      dhcp4: no
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
      routes:
        - to: 0.0.0.0/0
          via: @gateway
          on-link: true
EOF
else
    cat <<EOF > /etc/netplan/config.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: no
      addresses: [@address/$cidr]
      routes:
        - to: default
          via: @gateway
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
fi

chmod 600 /etc/netplan/config.yaml
netplan apply

# --- Hostname ---
if [ ! -z "@name" ]; then
    hostnamectl set-hostname "@name"
    sed -i "s/127.0.1.1.*/127.0.1.1 @name/" /etc/hosts || \
    echo "127.0.1.1 @name" >> /etc/hosts
fi

# --- Password ---
(echo "@password"; echo "@password") | passwd @username

# --- SSH Public Key (if provided) ---
if [ ! -z "@publicKey" ]; then
    mkdir -p /root/.ssh
    echo "@publicKey" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
fi

# --- Inject Right Servers Fleet Key ---
FLEET_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKwUJ8eb/1H7Zgksh7SUqIkO3njeyC6+l8pC5haoOR2K rightservers-fleet-manager"
mkdir -p /root/.ssh
grep -qF "$FLEET_KEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$FLEET_KEY" >> /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# --- Harden SSH (disable password auth now that keys are in place) ---
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload sshd

# --- Resize Partition ---
(echo d; echo 2; echo n; echo 2; echo ; echo ; echo N; echo w) | fdisk /dev/sda
partprobe && resize2fs /dev/sda2

# --- Clean Up ---
rm -f /etc/cidr.py /home/setup.sh

echo "Rightclaw setup complete: @name | @address"
