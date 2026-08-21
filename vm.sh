#!/bin/bash

# Runs on the host. The one entry point to the VMs kept in this directory: the
# commands live in scripts/ and are sourced rather than run, so a command and
# the helpers it leans on share one process and one copy of the constants they
# both read.

set -euo pipefail

# Resolved, so that a symlink to this script elsewhere on $PATH still finds the
# template, the instances and scripts/ next to the real one. Every command is
# written against this being the working directory.
cd "$(dirname "$(readlink -f "$0")")"

function usage() {
    cat <<EOF
Usage: $0 <command> [args]

  create <name> [options]   create a VM from the template
  delete <name> [--yes]     delete a VM and everything it owns
  net                       create the bridge the VMs share
  sync                      rewrite what this host keeps about the VMs

Run \`$0 <command> --help\` for a command's own options.
EOF
}

if [ $# -eq 0 ]; then
    usage >&2
    exit 1
fi

cmd=$1
shift

source scripts/common.sh

case $cmd in
    create) source scripts/create.sh; cmd_create "$@";;
    delete) source scripts/delete.sh; cmd_delete "$@";;
    net) source scripts/net.sh; cmd_net "$@";;
    sync) source scripts/sync.sh; cmd_sync "$@";;
    -h|--help) usage;;
    *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1;;
esac
