#!/bin/bash

# Runs on the host, not inside a VM.
#
# Every VM attaches to one shared bridge so the VMs can reach each other by a
# stable address. Compose cannot own that network: a project holding only a
# `networks` section is a no-op for `compose up` ("no service selected"), and
# letting one instance own it would make every other instance depend on that
# instance's lifetime. So the network is created here and referenced as
# `external` from each instance.

set -euo pipefail

name=vms_vmnet
subnet=172.28.1.0/24
gateway=172.28.1.1

if existing=$(docker network inspect "$name" -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null); then
    if [ "$existing" != "$subnet" ]; then
        echo "$name exists on $existing, expected $subnet." >&2
        exit 1
    fi
    echo "$name exists."
    exit 0
fi

docker network create \
    --driver bridge \
    --subnet "$subnet" \
    --gateway "$gateway" \
    "$name"
