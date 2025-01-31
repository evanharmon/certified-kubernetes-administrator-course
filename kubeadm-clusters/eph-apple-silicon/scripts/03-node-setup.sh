#!/usr/bin/env bash

# Adapted from kubernetes-the-hard-way and kodekloud-cka
# currently focused on use with multipass

# TODO: edit this file - just copy pasted so far from what I had edited locally

sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

# Support installing a specific version of kubernetes
# example: major / minor version aka `v1.31`
KUBE_LATEST=$(curl -L -s https://dl.k8s.io/release/stable.txt | awk 'BEGIN { FS="." } { printf "%s.%s", $1, $2 }')
KUBE_VERSION=${1:-$KUBE_LATEST}

# TODO: 04-kube-components.sh handles this as well, so have to overwrite files
sudo mkdir -p /etc/apt/keyrings

# install specific kubernetes version, overwrite if necessary
curl -fsSL  "https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/Release.key" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
# TODO this is broken
sudo apt-mark hold kubelet kubeadm kubectl

sudo crictl config \
    --set runtime-endpoint=unix:///run/containerd/containerd.sock \
    --set image-endpoint=unix:///run/containerd/containerd.sock

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS='--node-ip ${PRIMARY_IP}'
EOF
