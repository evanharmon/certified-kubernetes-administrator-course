#!/usr/bin/env bash

# Unfortunately, dhcpd leases are not removed when VM's are deleted by multipass
# have to be deleted manually with `sudo vi /var/db/dhcpd_leases`

# `-e` exit immediately if any command in pipeline has non-zero exit status
# `-u` exit on unset variables
# `-o pipefail` enable pipefail option
set -euo pipefail

# Usage:
#   bash deploy-with-multipass.sh <auto_deploy> <kube_version>
#
#
# Example usage:
#   Only setup nodes
#   `bash deploy-with-multipass.sh`
#   Setup nodes and install latest kubernetes components and tooling
#   `bash deploy-with-multipass.sh -auto`
#   Setup nodes and install specific kubernetes version components and tooling
#   `bash deploy-with-multipass.sh -auto v1.31`

auto_deploy=${1:-""}
kube_version=${2:-""}

# set variables for color type face
RED="\033[91m"
YELLOW="\033[93m"
GREEN="\033[92m"
BLUE="\033[94m" 
NC="\033[0m"

########################################################################
# print_color: prints a colorized message
#
# Description:
#   prints a message with a matching color and then resets the color.
#
# Usage:
#   How to call the function and any specific requirements.
#
# Arguments:
#   $1: color
#   $2: message
#
# Example:
#   print_color green "This is a test message."
########################################################################
function print_color() {
    local color=$1
    # remove color from args now that it's set
    shift
    local msg=""

    # using non-bold letters
    case $color in
        red)
            msg=$RED
            ;;
        yellow)
            msg=$YELLOW
            ;;
        green)
            msg=$GREEN
            ;;
        blue)
            msg=$BLUE
            ;;
        *)
        echo "Invalid color: $color" >&2
        return 1
        ;;
    esac

    # Print message with all remaining args and reset color
    echo -e "${msg}" "$@" "${NC}"
}

# Set the build mode
# "BRIDGE" - Places VMs on your local network so cluster can be accessed from browser.
#            You must have enough spare IPs on your network for the cluster nodes.
# "NAT"    - Places VMs in a private virtual network. Cluster cannot be accessed
#            without setting up a port forwarding rule for every NodePort exposed.
#            Use this mode if for some reason BRIDGE doesn't work for you.
BUILD_MODE="BRIDGE"

# Check that required tooling is available
# dump the output to null and just rely on checking exit code
if ! command -v jq > /dev/null; then
    print_color red "'jq' not found. Please install via the instructions below."
    echo "https://github.com/stedolan/jq/wiki/Installation#macos"
    exit 1
fi

if ! command -v multipass > /dev/null; then
    print_color red "'multipass' not found. Please install via the instructions below."
    echo "https://multipass.run/install"
    exit 1
fi

# Gather hardware information and worker nodes
# TODO: this should print out worker nodes
print_color yellow "---------------- DETERMINING WORKER NODES ----------------"
NUM_WORKER_NODES=2
# improvement - add constant
GB_IN_BYTES=1073741824 
MEM_GB=$(( $(sysctl hw.memsize | cut -d ' ' -f 2) / GB_IN_BYTES))
# Set the scripts path based on this script's location
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/scripts
VM_MEM_GB=3G

if [ $MEM_GB -lt 8 ]; then
    print_color red "System RAM is ${MEM_GB}GB. This is insufficient to deploy a working cluster."
    exit 1
fi

if [ $MEM_GB -lt 16 ]; then
    print_color yellow "System RAM is ${MEM_GB}GB. Deploying only one worker node."
    NUM_WORKER_NODES=1
    VM_MEM_GB=2G
    sleep 1
fi

workers=$(for n in $(seq 1 $NUM_WORKER_NODES); do echo -n "node0$n "; done)
print_color green "Done!"

# Determine interface for bridge
print_color yellow "---------------- DETERMINING INTERFACE FOR BRIDGE ----------------"
interface=""
bridge_arg="--bridged"

# Gather interfaces and find the first default - usually en0
for iface in $(multipass networks --format json | jq -r '.list[] | .name'); do
    if netstat -rn -f inet | grep "^default.*${iface}" > /dev/null; then
        interface=$iface
        break
    fi
done

if [ "$(multipass get local.bridged-network)" = "<empty>" ]; then
    print_color blue "Configuring bridge network..."

    if [ -z "${interface}" ]; then
        print_color yellow "No suitable interface detected for bridge."
        print_color yellow "Falling back to NAT installation."
        print_color yellow "Browser will not be able to connect to NodePort services."
        BUILD_MODE="NAT"
        bridge_arg=""
    else
        # Set bridge
        print_color green "Configuring bridge to interface '$(multipass networks | grep "${interface}")'"
        multipass set local.bridged-network="${interface}"
    fi
fi
print_color green "Done!"

# Prompt whether to rebuild nodes if running
print_color yellow "---------------- CHECKING FOR ACTIVE NODES ----------------"
# TODO: improve so it's not using hard-coded node names, should also print out the vm list
if multipass list --format json | jq -r '.list[].name' | grep -E '(controlplane|node01|node02)' > /dev/null; then
    # Set the text color and reset to default after prompt
    echo -n -e "$RED"
    read -r -p "VMs are running. Delete and rebuild them (y/n)? " ans
    echo -n -e "$NC"
    [ "$ans" != 'y' ] && exit 1
fi
print_color green "Done!"

# Delete, purge, and launch new nodes
print_color yellow "---------------- BOOTING NODES ----------------" 
for node in controlplane $workers; do
    if multipass list --format json | jq -r '.list[].name' | grep "$node"; then
        print_color yellow "Deleting ${node}."
        multipass delete "$node"
        multipass purge
    fi

    print_color blue "Launching ${node}."
    # TODO: could be improved to support non-hard coded values
    if ! multipass launch $bridge_arg --disk 5G --memory $VM_MEM_GB --cpus 2 --name "$node" jammy 2>/dev/null; then
        null
    else
        # confirm launch
        sleep 1
        if [ "$(multipass list --format json | jq -r --arg no "$node" '.list[] | select (.name == $no) | .state')" != "Running" ]; then
            print_color red "${node} failed to start!"
            exit 1
        fi
    fi

    print_color green "$node booted!"
done
print_color green "Done!"

# Create hostfile entries
print_color yellow "---------------- SETTING UP HOSTFILE ENTRIES OF NODES ----------------"
print_color blue "Setting hostnames."
hostentries=/tmp/hostentries
# Find the default interface IP and output CIDR block in `10.0.0` format
network=$(netstat -rn -f inet | grep "^default.*${interface}" | awk '{print $2}' | awk 'BEGIN { FS="." } { printf "%s.%s.%s", $1, $2, $3 }')
[ -f $hostentries ] && rm -f $hostentries

# Get multipass node info including ipv4 addresses
for node in controlplane $workers; do
    if [ "$BUILD_MODE" = "BRIDGE" ]; then
        ip=$(multipass info "$node" --format json | jq -r --arg nw 'first( .info[] )| .ipv4 | .[] | select(startswith($nw))')
    else
        ip=$(multipass info "$node" --format json | jq -r 'first( .info[] | .ipv4[0] )')
    fi
    echo "$ip $node" >> $hostentries
done
print_color green "Done!"

# Copy hostentries / host script and execute it
print_color yellow "---------------- COPYING HOSTENTRIES AND EXECUTING HOST SETUP SCRIPT"
# TODO: could be improved by setting script names to vars
for node in controlplane $workers; do
    multipass transfer $hostentries "$node":/tmp/
    multipass transfer "$SCRIPT_DIR"/01-host-setup.sh "$node":/tmp/
    multipass exec "$node" -- /tmp/01-host-setup.sh $BUILD_MODE "$network"
done

print_color green "Done!"

if [ "$auto_deploy" = "-auto" ]; then
    # set up hosts
    print_color blue "Setting up common components."
    # make local file to save join commands for multipass to share with other nodes
    join_command=/tmp/join-command.sh

    for node in controlplane $workers; do
        print_color blue "$node"
        multipass transfer $hostentries "$node":/tmp/
        multipass transfer "$SCRIPT_DIR"/*.sh "$node":/tmp/
        # TODO: could be improved by not hard-coding script names here
        multipass exec "$node" -- /tmp/02-kernel-setup.sh
        multipass exec "$node" -- /tmp/03-node-setup.sh "$kube_version"
        multipass exec "$node" -- /tmp/04-kube-components.sh "$kube_version"
    done

    print_color green "Done!"

    # Configure control plane
    print_color yellow "---------------- CONFIGURING CONTROL PLANE ----------------"
    # TODO: could be improved by not hard-coding controlplane node name but use var
    multipass exec controlplane /tmp/05-controlplane-deploy.sh
    # copy join-command locally to be made available to other nodes ia multipass
    multipass transfer controlplane:/tmp/join-command.sh $join_command
    print_color green "Done!"

    print_color yellow "---------------- CONFIGURING WORKERS ----------------"
    # TODO: there is a 06-deploy-worker.sh - renamed from 06-worker-workers.sh`
    # It's empty but available for further node customization
    for n in $workers; do
        print_color blue "Setting up $node."
        # copy over join command from local location
        multipass transfer $join_command "$n":/tmp
        multipass exec "$n" -- sudo $join_command
        print_color green "Done!"
    done
fi