# Sourced by vm.sh's create and delete. The one line each VM gets in
# /etc/hosts, which is what answers `ping my-vm` and `curl http://my-vm:3000`
# on this host: nsswitch here reads `files` before `dns`, and there is no DNS
# these names could come from -- Docker's own resolver listens inside each
# container's network namespace and is unreachable from the host.
#
# The file belongs to root and is shared with everything else on the machine,
# so it is rewritten whole, through sudo, rather than edited in place.

hosts_file=/etc/hosts
# Whose lines these are. Named apart from the readers below so that what gets
# written and what gets matched cannot drift.
hosts_marker=vm.sh

# The comment closing a line that belongs to a VM.
function hosts_mark() {
    echo "# $hosts_marker:$1"
}

# The file's lines, split by whether that comment closes them: `ours` for one
# VM's own line, `others` for everything else.
#
# Compared as text rather than matched as a pattern. A pattern would leave the
# marker needing to be escaped, and a substring match would be wrong besides:
# one VM's marker ends another's whenever one name begins the other, so `my-vm`
# would take `my-vm-2`'s line away with it. Trailing blanks are ignored so that
# a hand-tidied file still matches, and the whitespace the marker has to follow
# is what keeps a comment somebody wrote from counting as ours.
function hosts_lines() {
    awk -v mark="$(hosts_mark "$1")" -v want="$2" '
        {
            line = $0
            sub(/[[:space:]]+$/, "", line)
            head = substr(line, 1, length(line) - length(mark))
            ours = substr(line, length(head) + 1) == mark && head ~ /[[:space:]]$/
        }
        (ours ? "ours" : "others") == want
    ' "$hosts_file"
}

function host_entry() {
    hosts_lines "$1" ours
}

function hosts_without_entry() {
    hosts_lines "$1" others
}

# Refuses a name that something else in the file already answers to. /etc/hosts
# spells out `localhost` and this machine's own name, both of which a VM could
# legally be called, and a name silently shadowed there is worse than a name
# that never worked. A name mentioned in a comment counts as taken, which errs
# towards saying so.
function check_hosts_free() {
    local name=$1 others taken line

    others=$(hosts_without_entry "$name") || return 1

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

function set_host_entry() {
    local name=$1 addr=$2

    rewrite_hosts "$name" "$(printf '%s\t%s\t%s' "$addr" "$name" "$(hosts_mark "$name")")"
}

function drop_host_entry() {
    rewrite_hosts "$1"
}

# sed -i would replace the inode and take the file's ownership and mode with
# it, so the new text goes through a temporary that inherits both from the file
# it replaces -- root:adm here, root:root on other systems, neither ours to
# state. Nothing reaches the file before the move at the end, and a step that
# fails before then takes the temporary away with it.
#
# Every step is tested by hand rather than left to `set -e`: bash turns `set -e`
# off inside a function whose own failure the caller goes on to test, which is
# how both callers use this one, so an unchecked step here would pass unnoticed
# and take /etc/hosts with it.
function rewrite_hosts() {
    local name=$1 line=${2-} kept tmp

    # Read whole and on its own. Left inside the pipeline below, a file that
    # could not be read would arrive as nothing and be written back as nothing.
    kept=$(hosts_without_entry "$name") || return 1

    tmp=$(sudo mktemp "$hosts_file.vm.XXXXXX") || return 1

    if {
        if [ -n "$kept" ]; then
            printf '%s\n' "$kept"
        fi
        if [ -n "$line" ]; then
            printf '%s\n' "$line"
        fi
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
