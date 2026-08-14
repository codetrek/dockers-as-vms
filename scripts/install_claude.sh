#!/bin/bash

ver=$(claude --version)

if [ "$ver" == "" ]; then
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "claude $ver installed."
fi
