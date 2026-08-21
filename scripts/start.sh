# Sourced by docker-vm.sh. Brings a VM up. Compose is given the same pinned
# project and file that delete uses, so a stray COMPOSE_PROJECT_NAME or
# COMPOSE_FILE in the environment cannot aim it at another stack.

function usage_start() {
    cat <<EOF
Usage: $0 start <name>

Brings the VM up, building the runner image first if this host does not have it
yet. Already up, it comes to nothing.
EOF
}

function cmd_start() {
    local name='' addr

    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help) usage_start; return 0;;
            -*) echo "Unknown option: $1" >&2; usage_start >&2; return 1;;
            *) if [ -n "$name" ]; then
                   echo "Unexpected argument: $1" >&2
                   return 1
               fi
               name=$1; shift;;
        esac
    done

    if [ -z "$name" ]; then
        usage_start >&2
        return 1
    fi

    check_name "$name" || return 1

    if [ ! -f "$name/docker-compose.yml" ]; then
        echo "$name is not a VM here; \`$0 ls\` lists the ones that are." >&2
        return 1
    fi

    # Compose builds the image itself when this host has none, so a VM taken
    # from a fresh clone comes up on the same command as one that has run
    # before.
    (cd "$name" && docker compose -p "$name" -f docker-compose.yml up -d)

    addr=$(instance_addr "$name")

    cat <<EOF

$name is up at $addr. Log in with: ssh $name
EOF
}
