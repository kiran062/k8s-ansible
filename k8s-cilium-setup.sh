#!/bin/bash
set -e

#############################################
# CONFIG
#############################################
ROLE="$1"          # master | worker | delete
JOIN_CMD="$2"
POD_CIDR="192.168.0.0/16"
CILIUM_VERSION="1.15.6"
K8S_VERSION="v1.30"
#############################################

if [ -z "$ROLE" ]; then
  echo "Usage:"
  echo "  ./setup-k8s.sh master"
  echo "  ./setup-k8s.sh worker \"<kubeadm join command>\""
  echo "  ./setup-k8s.sh delete"
  exit 1
fi

################################################################################
# DELETE CLUSTER
################################################################################
if [ "$ROLE" = "delete" ]; then

  echo "Cleaning Kubernetes cluster..."

  sudo kubeadm reset -f || true
  rm -rf "$HOME/.kube"

  sudo rm -rf /etc/cni/net.d
  sudo rm -rf /var/lib/cni
  sudo rm -rf /etc/kubernetes
  sudo rm -rf /var/lib/etcd
  sudo rm -rf /var/lib/kubelet
  sudo rm -rf /var/lib/cilium

  sudo iptables -F || true
  sudo iptables -t nat -F || true
  sudo iptables -t mangle -F || true
  sudo iptables -X || true

  sudo apt-mark unhold kubeadm kubelet kubectl || true
  sudo apt remove -y kubeadm kubelet kubectl kubernetes-cni containerd || true

  sudo apt autoremove -y
  sudo apt clean

  echo "Cluster removed successfully."
  exit 0
fi

################################################################################
# PREREQUISITES
################################################################################
echo "Installing prerequisites..."

sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

sudo apt update -y
sudo apt install -y curl apt-transport-https ca-certificates gpg containerd

################################################################################
# CONTAINERD
################################################################################
echo "Configuring containerd..."

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

################################################################################
# KERNEL + SYSCTL
################################################################################
echo "Configuring kernel modules..."

sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
EOF

sudo sysctl --system

################################################################################
# KUBERNETES REPOSITORY
################################################################################
echo "Adding Kubernetes repository..."

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt update
sudo apt install -y kubeadm kubelet kubectl
sudo apt-mark hold kubeadm kubelet kubectl

################################################################################
# MASTER SETUP
################################################################################
if [ "$ROLE" = "master" ]; then

  echo "Initializing control plane..."

  sudo kubeadm init \
    --pod-network-cidr="$POD_CIDR" \
    | tee kubeadm-init.log

  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

  ################################################################################
  # INSTALL HELM
  ################################################################################
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  ################################################################################
  # INSTALL CILIUM (SAFE MODE)
  ################################################################################
  echo "Installing Cilium (VXLAN mode, kube-proxy enabled)..."

  helm repo add cilium https://helm.cilium.io/
  helm repo update

  helm install cilium cilium/cilium \
    --version "$CILIUM_VERSION" \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set tunnel=vxlan \
    --set kubeProxyReplacement=disabled

  echo "Waiting for Cilium rollout..."
  kubectl -n kube-system rollout status daemonset/cilium --timeout=5m

  echo
  echo "✅ Master node ready."
  echo
  echo "Worker join command:"
  grep "kubeadm join" kubeadm-init.log -A2

  exit 0
fi

################################################################################
# WORKER SETUP
################################################################################
if [ "$ROLE" = "worker" ]; then

  if [ -z "$JOIN_CMD" ]; then
    echo "Worker requires kubeadm join command"
    exit 1
  fi

  echo "Joining worker node..."
  sudo $JOIN_CMD

  echo "✅ Worker successfully joined."
  exit 0
fi

echo "Invalid role. Use master | worker | delete"
exit 1
