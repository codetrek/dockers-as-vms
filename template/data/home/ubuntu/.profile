# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

export GOPATH=$HOME/.local/go

test -d $HOME/bin && export PATH="$HOME/bin:$PATH"
test -d $HOME/.local/bin && export PATH="$HOME/.local/bin:$PATH"
test -d /usr/local/go && export PATH="/usr/local/go/bin:$HOME/.local/go/bin:$PATH"


