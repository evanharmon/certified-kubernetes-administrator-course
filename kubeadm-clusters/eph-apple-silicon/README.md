# APPLE SILICON MULTIPASS KUBERNETES PLAYGROUND

Adapted from kubernetes-the-hard-way and kodekloud-cka
currently focused on use with multipass on macs.
The changes are helpful to practice kubeadm upgrades / rollbacks

## Requirements
install [jq](https://github.com/stedolan/jq/wiki/Installation#macos) and [multipass](https://multipass.run/install)

## Run

### Create nodes
Only setup nodes
`bash deploy-with-multipass.sh`
Setup nodes and install latest kubernetes components and tooling
`bash deploy-with-multipass.sh -auto`
Setup nodes and install specific kubernetes version components and tooling
`bash deploy-with-multipass.sh -auto v1.31`

### Delete nodes
note you have to clean up some dhcp leases afterwards
`bash delete-with-multipass.sh`