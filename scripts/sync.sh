# Sourced by vm.sh. Puts what this host keeps about the VMs back in step with
# the VMs that are actually here: their block in /etc/hosts, their block in
# ~/.ssh/config, and each instance's own ssh settings.
#
# Everything it writes is derived from the instance directories, so it is the
# same work whether a VM has just been made, has just been taken away, or
# somebody edited a file by hand. That is why create and delete call it instead
# of each keeping their own way of adding and taking away a line: there is one
# way for these files to be right, and one piece of code that produces it.

source scripts/block.sh
source scripts/hosts.sh
source scripts/ssh.sh

function usage_sync() {
    cat <<EOF
Usage: $0 sync

Rewrites what this host keeps about the VMs from the instance directories: the
VMs' block in $hosts_file, their block in ~/.ssh/config, and each instance's
own ssh settings.

\`$0 create\` and \`$0 delete\` do this by themselves. Run it on its own to
repair a file that was edited by hand, or after moving the repository.
EOF
}

function sync_host() {
    local keys name addr hosts=

    keys=$(host_keys)

    while read -r name; do
        addr=$(instance_addr "$name")

        # Every instance has one, since create writes it and Compose will not
        # bring up a service whose network settings it cannot resolve. A file
        # edited down to nothing is better said out loud than skipped.
        if [ -z "$addr" ]; then
            echo "$name/docker-compose.yml names no ipv4_address." >&2
            return 1
        fi

        write_ssh_fragment "$name" "$addr" "$keys"
        hosts+=$(printf '%s\t%s' "$addr" "$name")$'\n'
    done < <(instances)

    write_hosts_block "${hosts%$'\n'}"
    write_ssh_block "Include $PWD/*/ssh_config"
}

function cmd_sync() {
    local name

    case ${1-} in
        "") ;;
        -h|--help) usage_sync; return 0;;
        *) echo "Unexpected argument: $1" >&2; usage_sync >&2; return 1;;
    esac

    sync_host

    while read -r name; do
        printf '%-24s %s\n' "$name" "$(instance_addr "$name")"
    done < <(instances)

    cat <<EOF

Written into $hosts_file, $ssh_config, and each instance's own ssh_config.
EOF
}
