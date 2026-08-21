# The shared network: what it is called, how it is addressed, and how it is put
# up. Sourced by vm.sh for the `net` command and by create.sh, which lays its
# VMs out inside this address plan. Runs on the host, not inside a VM.
#
# Every VM attaches to one shared bridge so the VMs can reach each other by a
# stable address. Compose cannot own that network: a project holding only a
# `networks` section is a no-op for `compose up` ("no service selected"), and
# letting one instance own it would make every other instance depend on that
# instance's lifetime. So the network is created here and referenced as
# `external` from each instance.

net=vms_vmnet
# A /24, which is the shape create's search for a free address is written
# against. The rest is derived from the prefix so the two cannot drift apart.
prefix=172.28.1
subnet=$prefix.0/24
gateway=$prefix.1

# The bridge outlives any one VM, so create calls this on every run and it has
# to come to nothing once the bridge is there. Silent either way: whether the
# bridge had to be made is plumbing, not something the caller asked about.
function ensure_network() {
    local existing

    if existing=$(docker network inspect "$net" -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null); then
        if [ "$existing" != "$subnet" ]; then
            echo "$net exists on $existing, expected $subnet." >&2
            return 1
        fi
        return 0
    fi

    docker network create \
        --driver bridge \
        --subnet "$subnet" \
        --gateway "$gateway" \
        "$net" >/dev/null
}

function usage_net() {
    cat <<EOF
Usage: $0 net

Creates $net ($subnet, gateway $gateway) unless it is already there.
\`$0 create\` does this by itself; this is for putting the bridge up on its own.
EOF
}

function cmd_net() {
    local existed=

    case ${1-} in
        "") ;;
        -h|--help) usage_net; return 0;;
        *) echo "Unexpected argument: $1" >&2; usage_net >&2; return 1;;
    esac

    # Asked before the fact, because afterwards the two cases look the same and
    # whether a bridge was just made is the one thing this command reports.
    if docker network inspect "$net" >/dev/null 2>&1; then
        existed=1
    fi

    ensure_network

    if [ -n "$existed" ]; then
        echo "$net was already up on $subnet, gateway $gateway."
    else
        echo "Created $net on $subnet, gateway $gateway."
    fi
}
