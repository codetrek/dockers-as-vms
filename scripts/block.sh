# Sourced by the two files that keep a section of their own inside something
# the host already owns: /etc/hosts and ~/.ssh/config. Neither file is ours, so
# what we put there is fenced between two markers and rewritten whole, and
# everything outside the fence is passed through untouched.

block_begin="# BEGIN vm.sh"
block_end="# END vm.sh"

# The block, given its lines as an argument.
function block() {
    echo "$block_begin"
    echo "# Written by \`vm.sh sync\` from the instance directories. What sits"
    echo "# between these markers is replaced whole; what sits outside them is"
    echo "# left alone."

    if [ -n "$1" ]; then
        printf '%s\n' "$1"
    fi

    echo "$block_end"
}

# A file without its block. Whole lines are compared, so a line that merely
# mentions a marker is not mistaken for one. A block left open -- an end marker
# taken out by hand -- would swallow the rest of the file, so that stops the
# run instead of quietly discarding somebody's config.
function without_block() {
    awk -v begin="$block_begin" -v end="$block_end" -v file="$1" '
        $0 == begin { inside = 1; next }
        $0 == end   { inside = 0; next }
        !inside
        END {
            if (inside) {
                printf "%s: \"%s\" with no matching \"%s\".\n", file, begin, end \
                    > "/dev/stderr"
                exit 1
            }
        }
    ' "$1"
}

# What a file's block says, without the markers or the notice under them.
function block_body() {
    awk -v begin="$block_begin" -v end="$block_end" '
        $0 == begin { inside = 1; next }
        $0 == end   { inside = 0; next }
        inside && $0 !~ /^[[:space:]]*#/
    ' "$1"
}
