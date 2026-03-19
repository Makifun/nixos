#!/bin/zsh
if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: ./sops_refresh_key.sh <ip/hostname> <flake_name>"
    exit 1
fi

HOST="$1"
FLAKE_NAME="$2"

PUBKEY=$(ssh-keyscan -t ed25519 "$HOST" 2>/dev/null | ssh-to-age)
if [[ -z "$PUBKEY" ]]; then
    echo "Failed to obtain age key from $HOST"
    exit 1
fi

echo "Obtained age key for $HOST (flake: $FLAKE_NAME):"
echo "$PUBKEY"

if grep -q "&hosts_$FLAKE_NAME\b" .sops.yaml; then
    sed -i "s/&hosts_$FLAKE_NAME .*/\&hosts_$FLAKE_NAME $PUBKEY/" .sops.yaml
    echo "Updated existing &hosts_$FLAKE_NAME in .sops.yaml"
else
    sed -i "/^keys:/a \  - &hosts_$FLAKE_NAME $PUBKEY" .sops.yaml
    sed -i "/- age:/a \          - *hosts_$FLAKE_NAME" .sops.yaml
    echo "Added new &hosts_$FLAKE_NAME to .sops.yaml"
fi

SECRETS_FILE="hosts/$FLAKE_NAME/secrets.yaml"
if [[ -f "$SECRETS_FILE" ]]; then
    echo "Re-encrypting $SECRETS_FILE with the updated keys..."
    sops updatekeys -y "$SECRETS_FILE"
else
    echo "No secrets file found at $SECRETS_FILE to re-encrypt."
fi
