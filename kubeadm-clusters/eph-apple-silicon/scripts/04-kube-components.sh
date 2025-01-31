#!/usr/bin/env bash

# Adapted from kubernetes-the-hard-way and kodekloud-cka
# currently focused on use with multipass

# Step 4 - Install kubeadm, kubelet and kubectl

# Support installing a specific version of kubernetes
# example: major / minor version aka `v1.31`
KUBE_LATEST=$(curl -L -s https://dl.k8s.io/release/stable.txt | awk 'BEGIN { FS="." } { printf "%s.%s", $1, $2 }')
KUBE_VERSION=${1:-$KUBE_LATEST}

sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl

# TODO: 03-node-setup.sh handles this as well, so have to overwrite files
sudo mkdir -p /etc/apt/keyrings

# Install specific kubernetes version
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/Release.key" \
    | sudo gpg --dearmor > /tmp/kubernetes-apt-keyring.gpg && \
    sudo mv /tmp/kubernetes-apt-keyring.gpg /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
