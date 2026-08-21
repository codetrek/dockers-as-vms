# Sourced by vm.sh. Everything this repository and this host know about one VM,
# gathered in one place: what it was made with, what Docker has done with it,
# and how to reach it.

function usage_show() {
    cat <<EOF
Usage: $0 show <name>

Prints one VM's settings, the state of its container and volume, and the ssh
settings that reach it.
EOF
}

function cmd_show() {
    local name='' status size volume identity

    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help) usage_show; return 0;;
            -*) echo "Unknown option: $1" >&2; usage_show >&2; return 1;;
            *) if [ -n "$name" ]; then
                   echo "Unexpected argument: $1" >&2
                   return 1
               fi
               name=$1; shift;;
        esac
    done

    if [ -z "$name" ]; then
        usage_show >&2
        return 1
    fi

    check_name "$name" || return 1

    if [ ! -f "$name/docker-compose.yml" ]; then
        echo "$name is not a VM here; \`$0 ls\` lists the ones that are." >&2
        return 1
    fi

    status=$(instance_status "$name")
    if [ -z "$status" ]; then
        status="not created"
    fi

    # Measuring the tree walks all of it, which for a VM that has been lived in
    # takes a moment. Worth it here, where a single VM was asked about by name.
    size=$(as_owner "$name" du -sh "$name" | cut -f1)

    cat <<EOF
$name
  status     $status
  address    $(instance_addr "$name")
  cpus       $(instance_field "$name" cpus)
  memory     $(instance_field "$name" mem_limit)
  directory  $PWD/$name ($size)
EOF

    while read -r volume; do
        [ -n "$volume" ] || continue
        printf '  volume     %s\n' "$volume"
    done <<<"$(instance_volumes "$name")"

    # Read back rather than worked out again: what is in the file is what ssh
    # will actually do, which is the point of asking.
    if [ ! -f "$name/ssh_config" ]; then
        echo "  ssh        no settings written; run \`$0 sync\`"
        return 0
    fi

    printf '  ssh        ssh %s\n' "$name"

    while read -r identity; do
        printf '  identity   %s\n' "$identity"
    done < <(sed -n 's/^ *IdentityFile *//p' "$name/ssh_config")
}
