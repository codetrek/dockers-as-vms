# Sourced by sync. The ssh settings that make `ssh my-vm` work. An address is
# not enough on its own: ssh would offer the host's own login name and every
# key it can find, while a VM knows only `ubuntu` and the key create authorised
# for it.
#
# Each VM's settings live in its own instance directory and are reached through
# one `Include` line, which is all that goes into ~/.ssh/config itself.

source scripts/block.sh

ssh_config=$HOME/.ssh/config

# The private halves of the host's keys, as `fingerprint path`. Anywhere under
# ~/.ssh counts, since where somebody keeps their keys below it is their own
# business. ssh-keygen costs a fork per key, so this is read once and handed to
# each fragment rather than rebuilt per instance.
function host_keys() {
    local pub private

    while read -r pub; do
        private=${pub%.pub}
        if [ -f "$private" ]; then
            printf '%s %s\n' "$(ssh-keygen -lf "$pub" | awk '{ print $2 }')" "$private"
        fi
    done < <(find -L "$HOME/.ssh" -name '*.pub' -type f | sort)
}

# The ones an instance authorises. An instance records only public halves and a
# fragment has to name a private one, so the two are matched by fingerprint
# here rather than remembered from whenever the VM was made -- which is what
# lets sync rebuild a fragment it did not write.
function instance_identities() {
    local name=$1 keys=$2 auth=$1/data/home/ubuntu/.ssh/authorized_keys
    local fingerprint

    if [ ! -e "$auth" ]; then
        return 0
    fi

    as_owner "$auth" ssh-keygen -lf "$auth" | awk '{ print $2 }' \
        | while read -r fingerprint; do
              awk -v want="$fingerprint" '$1 == want { print $2; exit }' <<<"$keys"
          done \
        | awk '!seen[$0]++'
}

function write_ssh_fragment() {
    local name=$1 addr=$2 keys=$3 private
    local identities=()

    mapfile -t identities < <(instance_identities "$name" "$keys")

    {
        echo "# Written by \`docker-vm.sh sync\`; goes with the instance directory."
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
        # file never collects keys for addresses that delete hands back to the
        # pool.
        echo "    UserKnownHostsFile $PWD/$name/known_hosts"
        echo "    StrictHostKeyChecking accept-new"
    } > "$name/ssh_config"
}

# The block goes at the top, and is moved back there if it has wandered: ssh
# keeps the first value it obtains for an option, and an ssh config commonly
# opens with settings meant for everything -- up to and including a bare
# `UserKnownHostsFile /dev/null`, which would throw away each VM's own.
function write_ssh_block() {
    local body=$1 kept='' target tmp

    if [ -e "$ssh_config" ]; then
        kept=$(without_block "$ssh_config") || return 1
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
        block "$body"
        if [ -n "$kept" ]; then
            printf '%s\n' "$kept"
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
