# Sourced by vm.sh. What every command needs: the names that belong to this
# repository rather than to a VM, and the shape a VM name has to take.

# The repository's own directories, plus the name the repository itself goes by
# as a Compose project. A VM named after this directory would take that project
# name, mixing the two up in every label and volume name Docker keeps for them.
reserved=(runner-image scripts template "$(basename "$PWD")")

# Compose names its project after the instance directory, lower-casing it and
# dropping everything outside [a-z0-9_-] on the way, so any other shape would
# leave the directory, the container and the `<project>_docker-disk` volume
# going by two or three different spellings:
# https://github.com/compose-spec/compose-go/blob/d70c053ec9cbd7180c7881ba769d277f5cfc6fb5/loader/loader.go#L760-L765
#
# For delete this doubles as the guard that keeps a path, a hidden entry or an
# option out of its `rm -rf`.
function check_name() {
    local name=$1 entry

    if [[ ! $name =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        echo "$name: a VM name takes lower-case letters, digits, - and _, and starts with a letter or a digit." >&2
        return 1
    fi

    for entry in "${reserved[@]}"; do
        if [ "$name" = "$entry" ]; then
            echo "$name belongs to this repository, not to a VM." >&2
            return 1
        fi
    done
}
