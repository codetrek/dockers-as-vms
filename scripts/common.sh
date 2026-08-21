# Sourced by vm.sh. What every command needs to know about this directory: the
# names that belong to the repository rather than to a VM, the shape a VM name
# has to take, and how to read the instances back off the disk.

# The repository's own directories, plus the name the repository itself goes by
# as a Compose project. A VM named after this directory would take that project
# name, mixing the two up in every label and volume name Docker keeps for them.
reserved=(runner-image scripts template "$(basename "$PWD")")

function reserved_name() {
    local entry

    for entry in "${reserved[@]}"; do
        if [ "$1" = "$entry" ]; then
            return 0
        fi
    done

    return 1
}

# Compose names its project after the instance directory, lower-casing it and
# dropping everything outside [a-z0-9_-] on the way, so any other shape would
# leave the directory, the container and the `<project>_docker-disk` volume
# going by two or three different spellings:
# https://github.com/compose-spec/compose-go/blob/d70c053ec9cbd7180c7881ba769d277f5cfc6fb5/loader/loader.go#L760-L765
#
# For delete this doubles as the guard that keeps a path, a hidden entry or an
# option out of its `rm -rf`.
function check_name() {
    local name=$1

    if [[ ! $name =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        echo "$name: a VM name takes lower-case letters, digits, - and _, and starts with a letter or a digit." >&2
        return 1
    fi

    if reserved_name "$name"; then
        echo "$name belongs to this repository, not to a VM." >&2
        return 1
    fi
}

# Every VM this directory holds. An instance brings a compose file along, which
# is what tells one from the rest of the repository once the reserved names --
# `template`, which brings one too -- are out of the way.
function instances() {
    local dir

    for dir in */; do
        dir=${dir%/}
        if [ -f "$dir/docker-compose.yml" ] && ! reserved_name "$dir"; then
            echo "$dir"
        fi
    done
}

# The address create wrote into an instance's compose file, which is the only
# record of it once the container is down.
function instance_addr() {
    sed -n 's/^ *ipv4_address: *"\?\([0-9.]*\).*/\1/p' "$1/docker-compose.yml"
}

# The bind-mount targets Docker creates belong to root, so reading what is
# under an instance, measuring it and removing it can each need more than our
# own rights.
function as_owner() {
    local tree=$1 foreign
    shift

    # On its own line, so that a failing find stops the run rather than reading
    # as "the tree is all ours" and sending `rm -rf` in without the rights it
    # needs -- inside an `if` condition, set -e would not see it.
    foreign=$(find "$tree" ! -uid "$(id -u)" -print -quit)

    if [ -n "$foreign" ]; then
        sudo "$@"
    else
        "$@"
    fi
}
