#!/bin/zsh
if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: ./nixos_install.sh <ip/hostname> <flake_name>"
    exit 1
fi

HOST="$1"
FLAKE_NAME="$2"

wait_port() {
    local port="$1" desc="$2"
    echo "Waiting for $desc on $HOST:$port..."
    until nc -z -w 2 "$HOST" "$port" 2>/dev/null; do sleep 2; done
    echo "$desc reachable."
}

if nc -z -w 2 "$HOST" 22 2>/dev/null; then
    echo "WARNING: $HOST already reachable on port 22 (existing system running)."
    read "REPLY?Continue? This will WIPE the disk. [y/N] "
    [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

echo "Pre-install: Refreshing sops keys for $FLAKE_NAME"
./sops_refresh_key.sh "$HOST" "$FLAKE_NAME" --no-push

echo "Installing flake .#$FLAKE_NAME on $HOST"
nix run github:nix-community/nixos-anywhere -- --flake .#$FLAKE_NAME --copy-host-keys $HOST

wait_port 2222 "initrd SSH (LUKS unlock)"
echo "Unlocking LUKS partitions"
ssh -tt -p 2222 root@$HOST <<< "$(rbw get ligma-luks)"

wait_port 22 "NixOS SSH"
echo "Post-install: Refreshing sops keys for $FLAKE_NAME"
./sops_refresh_key.sh "$HOST" "$FLAKE_NAME"

echo "Done xd"
