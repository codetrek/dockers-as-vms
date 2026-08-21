# Sourced by docker-vm.sh. Takes a VM down without taking it apart: the
# container and its disk stay where they are, so start brings the same machine
# back. Getting rid of one is delete's job.

function usage_stop() {
    cat <<EOF
Usage: $0 stop <name>

Stops the VM. Its container and its disk stay, so \`$0 start\` brings the
same machine back up. Already stopped, it comes to nothing.
EOF
}

function cmd_stop() {
    local name=''

    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help) usage_stop; return 0;;
            -*) echo "Unknown option: $1" >&2; usage_stop >&2; return 1;;
            *) if [ -n "$name" ]; then
                   echo "Unexpected argument: $1" >&2
                   return 1
               fi
               name=$1; shift;;
        esac
    done

    if [ -z "$name" ]; then
        usage_stop >&2
        return 1
    fi

    check_instance "$name" || return 1

    # Pinned the way start and delete pin it, so a stray COMPOSE_PROJECT_NAME
    # or COMPOSE_FILE in the environment cannot aim this at another stack.
    (cd "$name" && docker compose -p "$name" -f docker-compose.yml stop)

    cat <<EOF

$name is stopped. Bring it back with: $0 start $name
EOF
}
