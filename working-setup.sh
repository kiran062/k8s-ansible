#Run the below script in master as 
#./setup.sh master
#Run the below script in worker as
#./setup.sh worker "kubeadm join 172.31.32.96:6443 --token abn6ns.cc2thbx1uwrz98m7 \
        #--discovery-token-ca-cert-hash sha256:1bd68c158541845d1542adc284539db4fa4d7d6822921af2b8bfcefae14f2677"
        #<replcae the join command>
#And verify with the below command 
#kubectl get nodes
        
#!/bin/bash
set -e

### ---- CONFIG ---- ###
ROLE="$1"   # master | worker
JOIN_CMD="$2"
POD_CIDR="192.168.0.0/16"
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

# Update system packages
sudo apt update -y
sudo apt install -y curl apt-transport-https ca-certificates gpg

########################################
# Install containerd
########################################
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
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

########################################
# Sysctl
########################################
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
EOF

sudo sysctl --system

########################################
# Kubernetes Repo (correct for Noble)
########################################
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
# MASTER
################################################################################
if [ "$ROLE" = "master" ]; then
  echo "🌐 Initializing master node..."
  sudo kubeadm init --pod-network-cidr=$POD_CIDR | tee kubeadm-init.log

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  echo "📦 Installing Calico"
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

  echo
  echo "🎉 Master setup complete!"
  echo "👉 Copy this join command and run it on your worker:"
  grep "kubeadm join" kubeadm-init.log -A2
  echo
  exit 0
fi

################################################################################
# WORKER
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
