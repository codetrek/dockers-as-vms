#!/bin/bash

# Runs on the host. Undoes create_vm.sh: takes away the VM's container and the
# volume holding its Docker disk, then removes the instance directory. What the
# VMs share -- the bridge, the runner image, scripts/ -- is left alone.

set -euo pipefail

# Resolved, because everything below is measured against this directory: a
# symlink to the script elsewhere on $PATH would otherwise have it looking for
# instances wherever that link happens to live.
cd "$(dirname "$(readlink -f "$0")")"

# The repository's own directories, plus the name the repository itself goes by
# as a Compose project: an instance is never any of them.
reserved=(template scripts runner-image "$(basename "$PWD")")

assume_yes=
addr=

function usage() {
    cat <<EOF
Usage: $0 <name> [--yes]

  <name>   VM name: its directory, container and hostname
  --yes    delete without asking; required when there is no terminal to ask at
EOF
}

# What makes a container ours is the instance directory Compose rooted its
# project at, which is what this label records. A container merely going by the
# same name belongs to somebody else's project, and a host runs plenty of those.
function vm_containers() {
    docker ps -aq --filter "label=com.docker.compose.project.working_dir=$PWD/$name"
}

# Compose labels a volume with its project but never with a path, so this one
# cannot be tied back to the instance directory the way a container can. Going
# by the name the template's key produces is what still finds the disk of an
# instance whose directory and container are both already gone -- the state
# every stray `*_docker-disk` volume on a long-lived host is in -- and it takes
# a stranger's project to both go by this VM's name and declare a volume keyed
# `docker-disk` to be mistaken for one. Whatever matches is listed for
# confirmation before anything happens to it.
function vm_volumes() {
    docker volume ls -q \
        --filter "label=com.docker.compose.project=$name" \
        --filter "name=^${name}_docker-disk$"
}

# The bind-mount targets Docker creates belong to root, so both measuring the
# instance tree and removing it need more than our own rights.
function as_owner() {
    local foreign
    foreign=$(find "$name" ! -uid "$(id -u)" -print -quit)
    if [ -n "$foreign" ]; then
        sudo "$@"
    else
        "$@"
    fi
}

name=
while [ $# -gt 0 ]; do
    case $1 in
        --yes) assume_yes=1; shift;;
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

# The shape create_vm.sh accepts, which is what keeps the directory, the Compose
# project and the volume going by one spelling. Here it doubles as the guard
# that keeps a path, a hidden entry or an option out of the `rm -rf` below.
if [[ ! $name =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "$name: a VM name takes lower-case letters, digits, - and _, and starts with a letter or a digit." >&2
    exit 1
fi

for entry in "${reserved[@]}"; do
    if [ "$name" = "$entry" ]; then
        echo "$name belongs to this repository, not to a VM." >&2
        exit 1
    fi
done

# Following one would send `compose down` into whatever it points at while
# `rm -rf` took away no more than the link.
if [ -L "$name" ]; then
    echo "$name is a symlink, not an instance directory." >&2
    exit 1
fi

# The template brings one along and nothing else does, so a directory without it
# is somebody else's; better to say so than to recurse into it.
if [ -d "$name" ] && [ ! -f "$name/docker-compose.yml" ]; then
    echo "$name/ holds no docker-compose.yml, so it is not an instance; remove it by hand." >&2
    exit 1
fi

containers=$(vm_containers)
volumes=$(vm_volumes)

if [ ! -d "$name" ] && [ -z "$containers" ] && [ -z "$volumes" ]; then
    echo "Nothing called $name here: no directory, no container, no volume." >&2
    exit 1
fi

# Directory, Compose project, container labels and volume name are one name
# here, which is what `down` is pinned to below. An instance brought up under
# another project -- a `name:` added to its file, or COMPOSE_PROJECT_NAME set at
# the time -- would leave `down` with nothing to take and its volume behind, so
# stop at that rather than report a deletion that did not happen.
while read -r id; do
    [ -n "$id" ] || continue
    labelled=$(docker inspect "$id" --format '{{index .Config.Labels "com.docker.compose.project"}}')
    if [ "$labelled" != "$name" ]; then
        echo "$name is up as the Compose project $labelled; take that down by hand first." >&2
        exit 1
    fi
done <<<"$containers"

# The listing is what the question below is asking about, so both go to the
# terminal together; redirecting the script's output must not leave a bare
# "delete all of it?" behind.
{
    echo "About to delete $name"

    if [ -d "$name" ]; then
        addr=$(sed -n 's/^ *ipv4_address: *"\?\([0-9.]*\).*/\1/p' "$name/docker-compose.yml")
        size=$(as_owner du -sh "$name" | cut -f1)
        printf '  directory  %s (%s)\n' "$PWD/$name" "$size"
        if [ -n "$addr" ]; then
            printf '  address    %s\n' "$addr"
        fi
    fi

    while read -r id; do
        [ -n "$id" ] || continue
        # The format string goes through Docker rather than the shell, and it
        # arrives there stripped of leading blanks, so the indent is ours to add.
        printf '  container  %s\n' "$(docker ps -a --filter "id=$id" --format '{{.Names}} ({{.Status}})')"
    done <<<"$containers"

    while read -r volume; do
        [ -n "$volume" ] || continue
        printf '  volume     %s\n' "$volume"
    done <<<"$volumes"

    echo
} >&2

# Everything above is gone for good afterwards, so the answer has to be a
# deliberate yes. A run with nobody to ask stops instead of assuming one.
if [ -z "$assume_yes" ]; then
    if [ ! -t 0 ]; then
        echo "Not running interactively; pass --yes to delete $name unattended." >&2
        exit 1
    fi

    answer=
    read -rp "Delete all of it? [y/N]: " answer || true
    case $answer in
        [yY]*) ;;
        *) echo "Nothing deleted." >&2; exit 1;;
    esac
fi

echo "========== deleting $name =========="

# Compose knows the project's own containers and volumes, so let it do the work
# whenever the file naming them is still around. Project and file are pinned:
# COMPOSE_FILE or COMPOSE_PROJECT_NAME in the environment, or a stray .env in
# the instance directory, would otherwise aim `down` at another stack entirely.
# Orphans are left to the sweep below rather than to `--remove-orphans`, which
# reaches for the whole project name -- including a stranger's project going by
# the same one -- and would take away containers never listed above.
if [ -d "$name" ]; then
    (cd "$name" && docker compose -p "$name" -f docker-compose.yml down --volumes)
fi

# A directory deleted by hand leaves the container and the disk volume running
# and taking up room -- that is how a long-lived host ends up with stray
# `*_docker-disk` volumes -- so sweep up whatever else belongs to the instance.
# Read afresh, now that Compose has taken its own share away.
containers=$(vm_containers)
volumes=$(vm_volumes)

while read -r id; do
    [ -n "$id" ] || continue
    # Nothing to relay: the ids docker echoes back were listed above under their
    # names, and whatever goes wrong arrives on stderr instead.
    docker rm -f "$id" >/dev/null
done <<<"$containers"

while read -r volume; do
    [ -n "$volume" ] || continue
    docker volume rm "$volume" >/dev/null
done <<<"$volumes"

if [ -d "$name" ]; then
    as_owner rm -rf "$name"
fi

echo
if [ -n "$addr" ]; then
    echo "Deleted $name; $addr is free again."
else
    echo "Deleted $name."
fi
