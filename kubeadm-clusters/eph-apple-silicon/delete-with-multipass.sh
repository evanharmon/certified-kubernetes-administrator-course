#!/usr/bin/env bash

# Don't exit on unset variables
# `-e` exit immediately if any command in pipeline has non-zero exit status
# `-o pipefail` enable pipefail option
set -eo pipefail

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

# Gather hardware information and worker nodes
# TODO: this should print out worker nodes
print_color yellow "---------------- DETERMINING WORKER NODES ----------------"
NUM_WORKER_NODES=2
# improvement - add constant
GB_IN_BYTES=1073741824 
MEM_GB=$(( $(sysctl hw.memsize | cut -d ' ' -f 2) / GB_IN_BYTES))

[ $MEM_GB -lt 16 ] && NUM_WORKER_NODES=1

# TODO: this is pretty flaky and relies on hard-coded name format
workers=$(for n in $(seq 1 $NUM_WORKER_NODES); do echo -n "node0$n "; done)
print_color green "Done!"

# TODO: store actual workers / controlplane nodes and reference them here
function print_cleanup_message() {
    echo
    echo "You should now remove all the following lines from /var/db/dhcpd_leases"
    echo
    grep -E -A 5 -B 1 '(controlplane|node01|node02)' /var/db/dhcpd_leases
    echo
    cat <<EOF
Use the following command to do this

  sudo vi /var/db/dhcpd_leases

EOF
}

# TODO: probably should ask if snapshots are wanted and make them if necessary?
# currently assumes 1 controlplane node
print_color yellow "---------------- STOPPING AND DELETING NODES ----------------"
for n in $workers controlplane; do
    # TODO: improve by checking if nodes exist
    # multipass info "$n" 2> /dev/null
    # then check exit code, etc
    multipass stop "$n"
    multipass delete "$n"
done
print_color green "Done!"

print_color yellow "---------------- PURGING ALL DELETED NODES ----------------"
# TODO: this should be an option and potentially not auto-purge
multipass purge
print_color green "Done!"
print_cleanup_message