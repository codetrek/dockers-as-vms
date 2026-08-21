# Sourced by docker-vm.sh. Undoes create: takes away the VM's container and the
# volume holding its Docker disk, removes the instance directory, and takes the
# VM's name back off this host. What the VMs share -- the bridge, the runner
# image, the template -- is left alone.

source scripts/sync.sh

function usage_delete() {
    cat <<EOF
Usage: $0 delete <name> [--yes]

  <name>   VM name: its directory, container and hostname
  --yes    delete without asking; required when there is no terminal to ask at
EOF
}

function cmd_delete() {
    local name='' assume_yes='' addr='' answer=''
    local containers volumes size id labelled volume

    while [ $# -gt 0 ]; do
        case $1 in
            --yes) assume_yes=1; shift;;
            -h|--help) usage_delete; return 0;;
            -*) echo "Unknown option: $1" >&2; usage_delete >&2; return 1;;
            *) if [ -n "$name" ]; then
                   echo "Unexpected argument: $1" >&2
                   return 1
               fi
               name=$1; shift;;
        esac
    done

    if [ -z "$name" ]; then
        usage_delete >&2
        return 1
    fi

    check_name "$name" || return 1

    # Following one would send `compose down` into whatever it points at while
    # `rm -rf` took away no more than the link.
    if [ -L "$name" ]; then
        echo "$name is a symlink, not an instance directory." >&2
        return 1
    fi

    # The template brings one along and nothing else does, so a directory
    # without it is somebody else's; better to say so than to recurse into it.
    if [ -d "$name" ] && [ ! -f "$name/docker-compose.yml" ]; then
        echo "$name/ holds no docker-compose.yml, so it is not an instance; remove it by hand." >&2
        return 1
    fi

    containers=$(instance_containers "$name")
    volumes=$(instance_volumes "$name")

    if [ -d "$name" ]; then
        addr=$(instance_addr "$name")
    else
        # The instance directory is where the address is written down; once it
        # is gone, our own block in /etc/hosts is what still remembers it.
        addr=$(hosts_addr "$name")
    fi

    if [ ! -d "$name" ] && [ -z "$containers" ] && [ -z "$volumes" ] && [ -z "$addr" ]; then
        echo "Nothing called $name here: no directory, no container, no volume, no host entry." >&2
        return 1
    fi

    # Directory, Compose project, container labels and volume name are one name
    # here, which is what `down` is pinned to below. An instance brought up
    # under another project -- a `name:` added to its file, or
    # COMPOSE_PROJECT_NAME set at the time -- would leave `down` with nothing to
    # take and its volume behind, so stop at that rather than report a deletion
    # that did not happen.
    while read -r id; do
        [ -n "$id" ] || continue
        labelled=$(docker inspect "$id" --format '{{index .Config.Labels "com.docker.compose.project"}}')
        if [ "$labelled" != "$name" ]; then
            echo "$name is up as the Compose project $labelled; take that down by hand first." >&2
            return 1
        fi
    done <<<"$containers"

    # The listing is what the question below is asking about, so both go to the
    # terminal together; redirecting the command's output must not leave a bare
    # "delete all of it?" behind. The volume is matched by name rather than by
    # the path the container carries, so it is listed here for the same reason
    # the rest is: nothing goes without having been shown first.
    {
        echo "About to delete $name"

        if [ -d "$name" ]; then
            size=$(as_owner "$name" du -sh "$name" | cut -f1)
            printf '  directory  %s (%s)\n' "$PWD/$name" "$size"
        fi

        if [ -n "$addr" ]; then
            printf '  address    %s\n' "$addr"
        fi

        while read -r id; do
            [ -n "$id" ] || continue
            # The format string goes through Docker rather than the shell, and
            # it arrives there stripped of leading blanks, so the indent is ours
            # to add.
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
            return 1
        fi

        read -rp "Delete all of it? [y/N]: " answer || true
        case $answer in
            [yY]*) ;;
            *) echo "Nothing deleted." >&2; return 1;;
        esac
    fi

    echo "========== deleting $name =========="

    # Compose knows the project's own containers and volumes, so let it do the
    # work whenever the file naming them is still around. Project and file are
    # pinned: COMPOSE_FILE or COMPOSE_PROJECT_NAME in the environment, or a
    # stray .env in the instance directory, would otherwise aim `down` at
    # another stack entirely. Orphans are left to the sweep below rather than to
    # `--remove-orphans`, which reaches for the whole project name -- including
    # a stranger's project going by the same one -- and would take away
    # containers never listed above.
    if [ -d "$name" ]; then
        (cd "$name" && docker compose -p "$name" -f docker-compose.yml down --volumes)
    fi

    # A directory deleted by hand leaves the container and the disk volume
    # running and taking up room -- that is how a long-lived host ends up with
    # stray `*_docker-disk` volumes -- so sweep up whatever else belongs to the
    # instance. Read afresh, now that Compose has taken its own share away.
    containers=$(instance_containers "$name")
    volumes=$(instance_volumes "$name")

    while read -r id; do
        [ -n "$id" ] || continue
        # Nothing to relay: the ids docker echoes back were listed above under
        # their names, and whatever goes wrong arrives on stderr instead.
        docker rm -f "$id" >/dev/null
    done <<<"$containers"

    while read -r volume; do
        [ -n "$volume" ] || continue
        docker volume rm "$volume" >/dev/null
    done <<<"$volumes"

    if [ -d "$name" ]; then
        as_owner "$name" rm -rf "$name"
    fi

    # The instance's own ssh settings and known_hosts went with its directory.
    # What is left is on the host: its line among the VMs, which sync takes
    # away by writing the block without it, and whatever the shared known_hosts
    # remembers about a name and an address that are both about to belong to
    # somebody else.
    sync_host
    forget_host_keys "$name" "$addr"

    echo
    if [ -n "$addr" ]; then
        echo "Deleted $name; $addr is free again."
    else
        echo "Deleted $name."
    fi
}
