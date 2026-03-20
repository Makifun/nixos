#!/bin/zsh
if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: ./nixos_install.sh <ip/hostname> <flake_name>"
    exit 1
fi

HOST="$1"
FLAKE_NAME="$2"

echo "Pre-install: Refreshing sops keys for $FLAKE_NAME"
./sops_refresh_key.sh "$HOST" "$FLAKE_NAME" --no-push

echo "Installing flake .#$FLAKE_NAME on $HOST"
nix run github:nix-community/nixos-anywhere -- --flake .#$FLAKE_NAME --copy-host-keys $HOST

echo "Unlocking LUKS partitions"
ssh -o ConnectTimeout=10 root@$HOST -p 2222

echo "Waiting for boot to finish (15s)"
sleep 15

echo "Post-install: Refreshing sops keys for $FLAKE_NAME"
./sops_refresh_key.sh "$HOST" "$FLAKE_NAME"

echo "Done xd"
