#!/bin/bash

# Go itself lands in /usr/local/go and `go install` drops binaries into
# $GOPATH/bin. Neither directory is on PATH until the next login, so we prepend
# them here: without this the toolchain we just unpacked is invisible to the
# rest of this run and every `go install` below fails.
#
# GOPATH is set by .profile, which only runs for login shells: a non-interactive
# `ssh vm ~/scripts/install_golang.sh`, or sudo with its env_reset, would
# otherwise install into Go's default ~/go, which nothing ever puts on PATH.
export GOPATH="${GOPATH:-$HOME/.local/go}"
export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"

ver=1.26.6

function arch() {
    case $(uname -m) in
        x86_64*) echo amd64;;
        aarch64) echo arm64;;
        *) echo "";;
    esac
}

function install_pack() {
    local installed
    installed=$(command -v "$1") || true

    echo "========== checking $1 =========="
    if [ "$installed" != "" ]; then
        echo "$installed installed."
        return 0
    fi

    go install "$2" || exit 1
}

arch=$(arch)

test "$arch" == "" && echo "Arch $(uname -m) not supported" && exit 1

echo "========== checking golang =========="
installed=$(command -v go)
if [ "$installed" == "" ]; then
    pack=go${ver}.linux-${arch}.tar.gz
    curl -fSL "https://dl.google.com/go/$pack" -o /tmp/$pack || exit 1
    sudo tar -zxf /tmp/$pack -C /usr/local/ || exit 1
    rm -f /tmp/$pack
else
    echo "$(go version) installed."
fi

install_pack gopls golang.org/x/tools/gopls@latest
install_pack dlv github.com/go-delve/delve/cmd/dlv@latest
install_pack goimports golang.org/x/tools/cmd/goimports@latest
install_pack staticcheck honnef.co/go/tools/cmd/staticcheck@latest
install_pack govulncheck golang.org/x/vuln/cmd/govulncheck@latest

echo
echo All Done!
