✅ PART 1: AWS SETUP (DO THIS FIRST)
1️⃣ Create / Verify VPC

Example:

VPC CIDR: 10.0.0.0/16

2️⃣ Create Subnets
Public Subnet (for NAT)
CIDR: 10.0.0.0/24
Auto-assign Public IP: ENABLED

Private Subnet (for private EC2)
CIDR: 10.0.1.0/24
Auto-assign Public IP: DISABLED

3️⃣ Internet Gateway
Create IGW
Attach to VPC

4️⃣ Route Tables
Public Route Table

Associate with Public Subnet

0.0.0.0/0 → Internet Gateway (igw-xxxx)

Private Route Table

Associate with Private Subnet

0.0.0.0/0 → NAT Instance ID (i-xxxx)


❌ DO NOT use IGW here
❌ DO NOT use NAT Gateway

5️⃣ Launch NAT Instance (IMPORTANT SETTINGS)
AMI
Ubuntu Server 22.04 LTS

Subnet
Public Subnet

Auto-assign Public IP
ENABLED

6️⃣ Disable Source/Destination Check (MANDATORY)
EC2 → NAT instance
Actions → Networking → Change source/destination check → Disable


If this is not disabled → internet will NEVER work

7️⃣ Security Groups
NAT Instance SG

Inbound:

All traffic | Source: Private subnet CIDR (10.0.1.0/24)


Outbound:

All traffic | 0.0.0.0/0

Private Instance SG

Outbound:

All traffic | 0.0.0.0/0


Inbound: anything you need (SSH from bastion, etc.)

✅ PART 2: SINGLE SCRIPT FOR NAT INSTANCE (UBUNTU)

👉 SSH into NAT instance and run this once.

#!/bin/bash
set -e

echo "🔍 Detecting primary network interface..."
IFACE=$(ip route | grep default | awk '{print $5}')

echo "✅ Network interface detected: $IFACE"

echo "🚀 Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

echo "🔥 Configuring iptables NAT..."
sudo iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
sudo iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE

echo "💾 Installing iptables-persistent..."
sudo apt update -y
sudo apt install -y iptables-persistent

echo "💾 Saving iptables rules..."
sudo netfilter-persistent save

echo "📋 Current NAT table:"
sudo iptables -t nat -L -n -v

echo "✅ NAT Instance configuration completed successfully!"
