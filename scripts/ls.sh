# Sourced by docker-vm.sh. What VMs are here, and what state each is in.
# Everything comes off the disk and out of Docker, so a VM that has never been
# started lists the same as one that is up.

function usage_ls() {
    cat <<EOF
Usage: $0 ls

Lists every VM in this directory with its address, its limits and what Docker
says about its container.
EOF
}

function cmd_ls() {
    local name status

    case ${1-} in
        "") ;;
        -h|--help) usage_ls; return 0;;
        *) echo "Unexpected argument: $1" >&2; usage_ls >&2; return 1;;
    esac

    if [ -z "$(instances)" ]; then
        echo "No VMs here yet. Make one with \`$0 create <name>\`."
        return 0
    fi

    {
        printf 'NAME\tADDRESS\tCPUS\tMEMORY\tSTATUS\n'

        while read -r name; do
            status=$(instance_status "$name")

            # Docker has nothing to say about a VM that was created but never
            # brought up, and an empty column would leave the row short.
            if [ -z "$status" ]; then
                status="not created"
            fi

            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$name" \
                "$(instance_addr "$name")" \
                "$(instance_field "$name" cpus)" \
                "$(instance_field "$name" mem_limit)" \
                "$status"
        done < <(instances)
    } | column -t -s "$(printf '\t')"
}
