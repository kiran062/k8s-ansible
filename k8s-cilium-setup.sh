#!/bin/bash
set -e

### ---- CONFIG ---- ###
ROLE="$1"   # master | worker
JOIN_CMD="$2"
POD_CIDR="192.168.0.0/16"
CILIUM_VERSION="1.15.6"
########################

if [ -z "$ROLE" ]; then
  echo "Usage:"
  echo "  setup-k8s.sh master"
  echo "  setup-k8s.sh worker \"<kubeadm join command>\""
  exit 1
fi

echo "🚀 Installing Kubernetes prerequisites..."

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Update packages
sudo apt update -y
sudo apt install -y curl apt-transport-https ca-certificates gpg

########################################
# Install containerd
########################################
echo "📦 Installing containerd..."
sudo apt install -y containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Enable systemd cgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

########################################
# Kernel modules
########################################
echo "🔧 Configuring kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

########################################
# Sysctl
########################################
echo "🔧 Applying sysctl settings..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
EOF

sudo sysctl --system

########################################
# Kubernetes Repo
########################################
echo "📦 Adding Kubernetes repository..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubeadm kubelet kubectl
sudo apt-mark hold kubeadm kubelet kubectl

echo "✔️ Kubernetes components installed."

################################################################################
# MASTER SETUP
################################################################################
if [ "$ROLE" = "master" ]; then
  echo "🌐 Initializing master node..."
  sudo kubeadm init --pod-network-cidr=$POD_CIDR | tee kubeadm-init.log

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  ################################################################################
  # Install Helm
  ################################################################################
  echo "📦 Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  ################################################################################
  # Install Cilium CNI
  ################################################################################
  echo "🚀 Installing Cilium CNI..."

  helm repo add cilium https://helm.cilium.io/
  helm repo update

  helm install cilium cilium/cilium \
    --version $CILIUM_VERSION \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=false \
    --set ipv4NativeRoutingCIDR=$POD_CIDR

  echo "⏳ Waiting for Cilium to be ready..."
  kubectl -n kube-system rollout status daemonset/cilium --timeout=5m

  echo
  echo "🎉 Master setup complete with Cilium!"
  echo "👉 Copy this join command and run it on your worker:"
  grep "kubeadm join" kubeadm-init.log -A2
  echo
  exit 0
fi

################################################################################
# WORKER SETUP
################################################################################
if [ "$ROLE" = "worker" ]; then
  if [ -z "$JOIN_CMD" ]; then
    echo "❗ Worker requires kubeadm join command"
    exit 1
  fi

  echo "🔗 Joining worker to cluster..."
  sudo $JOIN_CMD

  echo "✔️ Worker successfully joined!"
  exit 0
fi

echo "⚠️ ROLE must be master or worker"
