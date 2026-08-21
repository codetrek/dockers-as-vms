# Sourced by sync. The block /etc/hosts carries for the VMs, which is what
# answers `ping my-vm` and `curl http://my-vm:3000` on this host: nsswitch here
# reads `files` before `dns`, and there is no DNS these names could come from
# -- Docker's own resolver listens inside each container's network namespace
# and is unreachable from the host.
#
# The file belongs to root and is shared with everything else on the machine,
# so it is rewritten whole, through sudo, rather than edited in place.

source scripts/block.sh

hosts_file=/etc/hosts

# Refuses a name that something outside our block already answers to.
# /etc/hosts spells out `localhost` and this machine's own name, both of which
# a VM could legally be called, and a name silently shadowed there is worse
# than a name that never worked. A name mentioned in a comment counts as taken,
# which errs towards saying so.
function check_hosts_free() {
    local name=$1 others taken line

    others=$(without_block "$hosts_file") || return 1

    # grep says nothing matched by exiting 1, which here is the good outcome;
    # anything worse is a file we could not read and has to stop the run.
    taken=$(grep -E "[[:space:]]$name([[:space:]]|#|\$)" <<<"$others") \
        || [ $? -eq 1 ] || return 1

    if [ -n "$taken" ]; then
        echo "$name is already spoken for in $hosts_file:" >&2
        while read -r line; do
            printf '  %s\n' "$line" >&2
        done <<<"$taken"
        return 1
    fi
}

# The address our block gives a name. This is where it comes from once the
# instance directory that recorded it is gone.
function hosts_addr() {
    block_body "$hosts_file" | awk -v name="$1" '$2 == name { print $1 }'
}

# sed -i would replace the inode and take the file's ownership and mode with
# it, so the new text goes through a temporary that inherits both from the file
# it replaces -- root:adm here, root:root on other systems, neither ours to
# state. Nothing reaches the file before the move at the end, and a step that
# fails before then takes the temporary away with it.
#
# Every step is tested by hand rather than left to `set -e`: bash turns `set -e`
# off inside a function whose own failure the caller goes on to test, which is
# how this one is called, so an unchecked step here would pass unnoticed and
# take /etc/hosts with it.
function write_hosts_block() {
    local body=$1 kept tmp

    # Read whole and on its own. Left inside the pipeline below, a file that
    # could not be read would arrive as nothing and be written back as nothing.
    kept=$(without_block "$hosts_file") || return 1

    tmp=$(sudo mktemp "$hosts_file.vm.XXXXXX") || return 1

    # Appended: nothing in /etc/hosts turns on the order of its entries, and
    # what was already there is better left where the reader expects it.
    if {
        if [ -n "$kept" ]; then
            printf '%s\n' "$kept"
        fi
        block "$body"
    } | sudo tee "$tmp" >/dev/null \
        && sudo chown --reference="$hosts_file" "$tmp" \
        && sudo chmod --reference="$hosts_file" "$tmp" \
        && sudo mv -f "$tmp" "$hosts_file"
    then
        return 0
    fi

    sudo rm -f "$tmp"
    return 1
}
