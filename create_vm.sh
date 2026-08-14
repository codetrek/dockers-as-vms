#!/bin/bash

# Runs on the host. Creates a VM instance from template/: ensures the shared
# bridge exists, copies the skeleton, and fills in the compose placeholders with
# a free address. Starting it is left to the caller.

set -euo pipefail

cd "$(dirname "$0")"

net=vms_vmnet
# Docker allocates dynamic addresses from the bottom of the pool, so static
# assignments start higher up to stay clear of them.
first_host=10
# The image's ubuntu user; the bind-mounted home must be owned by it or sshd
# refuses the key ("bad ownership or modes") under StrictModes.
vm_uid=1000
vm_gid=1000

default_cpus=2
default_mem=4g
cpus=
mem=
addr=

function usage() {
    cat <<EOF
Usage: $0 <name> [--ip ADDR] [--cpus N] [--mem SIZE]

  <name>       VM name, used as the directory, container name and hostname
  --ip ADDR    static address on the shared bridge (default: lowest free host
               address from .${first_host})
  --cpus N     CPU limit, asked for interactively when omitted (default: ${default_cpus})
  --mem SIZE   memory limit, asked for interactively when omitted (default: ${default_mem})
EOF
}

# Sizing is prompted for rather than silently defaulted, since it is the one
# thing worth thinking about per VM. A non-interactive run takes the default
# instead of blocking, and end-of-input counts as accepting it.
function ask() {
    local prompt=$1 default=$2 answer=

    if [ -t 0 ]; then
        read -rp "$prompt [$default]: " answer || true
    fi

    echo "${answer:-$default}"
}

# Addresses already spoken for: live containers on the bridge, plus the static
# assignments of instances that happen to be down right now.
function used_addrs() {
    docker network inspect "$net" -f '{{range .Containers}}{{.IPv4Address}}{{"\n"}}{{end}}' \
        | cut -d/ -f1
    grep -rhoE '^\s*ipv4_address:\s*"?[0-9.]+' ./*/docker-compose.yml 2>/dev/null \
        | grep -oE '[0-9.]+$' || true
}

function free_addr() {
    local used host
    used=$(used_addrs | sort -u)
    for host in $(seq "$first_host" 254); do
        if ! grep -qxF "$prefix.$host" <<<"$used"; then
            echo "$prefix.$host"
            return 0
        fi
    done
    echo "No free address left in $prefix.0/24" >&2
    return 1
}

name=
while [ $# -gt 0 ]; do
    case $1 in
        --ip) addr=$2; shift 2;;
        --cpus) cpus=$2; shift 2;;
        --mem) mem=$2; shift 2;;
        -h|--help) usage; exit 0;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
        *) if [ -n "$name" ]; then
               echo "Unexpected argument: $1" >&2
               exit 1
           fi
           name=$1; shift;;
    esac
done

if [ -z "$name" ]; then
    usage >&2
    exit 1
fi

if [ -e "$name" ]; then
    echo "$name already exists." >&2
    exit 1
fi

./vmnet.sh

# vmnet.sh owns the addressing; read it back rather than restating it here.
subnet=$(docker network inspect "$net" -f '{{(index .IPAM.Config 0).Subnet}}')
case $subnet in
    *.0/24) prefix=${subnet%.0/24};;
    *) echo "$net is $subnet; this script assumes a /24." >&2; exit 1;;
esac

if [ -z "$addr" ]; then
    addr=$(free_addr)
fi

if [ -z "$cpus" ]; then
    cpus=$(ask "CPUs" "$default_cpus")
fi

if [ -z "$mem" ]; then
    mem=$(ask "Memory" "$default_mem")
fi

echo "========== creating $name =========="
cp -r template "$name"

sed -i \
    -e "s|^\( *\)container_name: .*|\1container_name: $name|" \
    -e "s|^\( *\)hostname: .*|\1hostname: $name|" \
    -e "s|^\( *\)ipv4_address: .*|\1ipv4_address: $addr|" \
    -e "s|^\( *\)cpus: .*|\1cpus: $cpus|" \
    -e "s|^\( *\)mem_limit: .*|\1mem_limit: $mem|" \
    "$name/docker-compose.yml"

# A template edit that renames or reshapes those keys would leave placeholders
# behind, which Compose accepts and Docker then rejects at container creation.
if grep -q '<.*>' "$name/docker-compose.yml"; then
    echo "Unsubstituted placeholders left in $name/docker-compose.yml:" >&2
    grep -n '<.*>' "$name/docker-compose.yml" >&2
    rm -rf "$name"
    exit 1
fi

# The home tree ships with the template and must match the ubuntu user or sshd
# rejects the key. /root, /usr/local and /opt are left for Docker to create as
# root, matching how the existing instances came about; vm-startup.sh hands /opt
# to ubuntu at boot.
if [ "$(stat -c %u "$name/data/home")" != "$vm_uid" ]; then
    sudo chown -R "$vm_uid:$vm_gid" "$name/data/home"
fi

(cd "$name" && docker compose config >/dev/null)

cat <<EOF

Created $name/
  container $name
  hostname  $name
  address   $addr
  cpus      $cpus
  memory    $mem

Start it with: cd $name && docker compose up -d
EOF
