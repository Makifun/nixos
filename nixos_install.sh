#!/bin/zsh
if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: ./nixos_install.sh <ip/hostname> <flake_name>"
    exit 1
fi

HOST="$1"
FLAKE_NAME="$2"

echo "Installing flake .#$FLAKE_NAME on $HOST"
nix run github:nix-community/nixos-anywhere -- --flake .#$FLAKE_NAME --copy-host-keys $HOST

echo "Done xd"
