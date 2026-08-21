#!/bin/bash

test -f "$HOME/.nvm/nvm.sh" && source $HOME/.nvm/nvm.sh

echo "========== checking nvm ==========="
if [ "$(nvm --version)" == "" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash
    \. "$HOME/.nvm/nvm.sh"
else
    echo "nvm $(nvm --version) installed."
fi

echo "========== checking node =========="
# Download and install node
if [ "$(node --version 2>/dev/null)" == "" ]; then
    nvm install 24
else
    echo "node $(node --version) installed."
fi

echo "========== checking pnpm =========="
if [ "$(pnpm -v 2>/dev/null)" == "" ]; then
    # Download and install pnpm:
    corepack enable pnpm
else
    echo "pnpm $(pnpm -v 2>/dev/null) installed."
fi

echo Done
