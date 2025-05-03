# APPLE SILICON MULTIPASS KUBERNETES PLAYGROUND

Adapted from kubernetes-the-hard-way and kodekloud-cka
currently focused on use with multipass on macs.
The changes are helpful to practice kubeadm upgrades / rollbacks

## Alternative
for an HAproxy setup, via terraform, that allows `kubectl` commands from macOS localhost use:
- [https://github.com/evanharmon/eph-terraform-kubernetes-multipass](https://github.com/evanharmon/eph-terraform-kubernetes-multipass)

## Requirements
install:
- [jq](https://github.com/stedolan/jq/wiki/Installation#macos)
- [multipass](https://multipass.run/install)

## Limitations
- single controlplane server
- have to multipass shell in to controlplane to run kubectl commands

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
```sh
bash delete-with-multipass.sh
sudo vi /var/db/dhcpd_leases
```

## Multipass

```sh
# List machines
multipass list
# shell in to a machine
multipass shell master-0
```

### Cannot connect to socket on macOS
close multipass GUI if it's open - this'll fix it either way

```bash
sudo launchctl unload /Library/LaunchDaemons/com.canonical.multipassd.plist
sudo launchctl load /Library/LaunchDaemons/com.canonical.multipassd.plist
```
