# Sourced by vm.sh's create and delete. The ssh config fragment each VM gets,
# which is what makes `ssh my-vm` work. An address is not enough on its own:
# ssh would offer the host's own login name and every key it can find, while a
# VM knows only `ubuntu` and the key create authorised for it.
#
# The fragment lives in the instance directory and is reached through one
# `Include` line, so that deleting a VM takes its ssh settings with it.

ssh_config=$HOME/.ssh/config

# A directive as ssh reads it: the keyword without regard to case, indentation
# and runs of whitespace immaterial. Two lines saying the same thing have to
# compare equal, or the include below gets written a second time.
function ssh_directive() {
    awk '{ $1 = tolower($1); print }' <<<"$1"
}

function write_ssh_fragment() {
    local name=$1 addr=$2 pub private
    local identities=()

    shift 2
    for pub in "$@"; do
        # Resolved, because ssh opens a relative IdentityFile against whatever
        # directory it was run from rather than against the config naming it,
        # and a key given as `--key ../keys/mine.pub` would then be found from
        # this repository and nowhere else.
        private=$(readlink -f "${pub%.pub}")
        # A key authorised from somebody else's .pub has no private half here;
        # naming it would leave ssh complaining about a file that is not ours
        # to produce.
        if [ -f "$private" ]; then
            identities+=("$private")
        fi
    done

    {
        echo "# Written by vm.sh create; goes away with the instance directory."
        # Both spellings, so that reaching the VM by address also gets the
        # known_hosts below rather than whatever an earlier tenant of that
        # address left behind in the shared one.
        echo "Host $name $addr"
        echo "    HostName $addr"
        echo "    User ubuntu"

        for private in "${identities[@]}"; do
            echo "    IdentityFile $private"
        done

        # Without this ssh works through everything the agent holds before the
        # key that was authorised, and sshd hangs up after six tries. Left out
        # when we have no identity to name, since then it would leave ssh with
        # nothing at all to offer.
        if [ ${#identities[@]} -gt 0 ]; then
            echo "    IdentitiesOnly yes"
        fi

        # Remembered per instance and thrown away with it, so that the shared
        # file never accumulates keys for addresses that delete hands back to
        # the pool.
        echo "    UserKnownHostsFile $PWD/$name/known_hosts"
        echo "    StrictHostKeyChecking accept-new"
    } > "$name/ssh_config"
}

# ssh keeps the first value it obtains for an option, so the VMs have to be
# included before anything else the file states -- not merely before its first
# `Host` block. Options are allowed on their own above any block, and it is
# exactly those that would otherwise apply to every VM: a bare
# `UserKnownHostsFile /dev/null` up there would throw away each VM's own.
function ensure_ssh_include() {
    local line="Include $PWD/*/ssh_config" want body first existing target tmp
    local directives=()

    want=$(ssh_directive "$line")

    if [ -f "$ssh_config" ]; then
        body=$(cat "$ssh_config") || return 1
        # Same normalisation as ssh_directive, over the whole file at once and
        # skipping what ssh ignores.
        mapfile -t directives < <(awk '!/^[[:space:]]*(#|$)/ { $1 = tolower($1); print }' <<<"$body")

        first=${directives[0]-}

        if [ "$first" = "$want" ]; then
            return 0
        fi

        for existing in "${directives[@]}"; do
            if [ "$existing" = "$want" ]; then
                echo "$ssh_config includes the VMs, but only after \`$first\`." >&2
                echo "Move \`$line\` to the top: ssh keeps the first value it obtains." >&2
                return 1
            fi
        done
    fi

    if [ ! -d "$(dirname "$ssh_config")" ]; then
        mkdir -m 700 "$(dirname "$ssh_config")"
    fi

    # Followed, so that a config symlinked out of a dotfiles tree is rewritten
    # where it lives rather than replaced by a regular file of our own.
    target=$ssh_config
    if [ -e "$ssh_config" ]; then
        target=$(readlink -f "$ssh_config")
    fi

    tmp=$(mktemp "$target.vm.XXXXXX")
    {
        echo "$line"
        if [ -f "$ssh_config" ]; then
            cat "$ssh_config"
        fi
    } > "$tmp"

    if [ -f "$target" ]; then
        chmod --reference="$target" "$tmp"
    else
        chmod 600 "$tmp"
    fi

    mv -f "$tmp" "$target"
}

# The instance's own known_hosts goes with its directory. What this clears is
# the shared file, where a VM reached by address before any of this existed
# left a key that the next tenant of that address would be accused over.
function forget_host_keys() {
    local known=$HOME/.ssh/known_hosts entry

    if [ ! -f "$known" ]; then
        return 0
    fi

    for entry in "$@"; do
        [ -n "$entry" ] || continue
        # Asked before it is told: -R reports a miss at length and on stderr,
        # which is where a real failure has to stay visible, and a shared file
        # holding nothing for this VM is the ordinary case. What it says when
        # it does find something -- the file rewritten, the previous contents
        # kept as known_hosts.old -- is worth seeing and is left alone.
        if ssh-keygen -F "$entry" -f "$known" >/dev/null; then
            ssh-keygen -q -R "$entry" -f "$known"
        fi
    done
}
