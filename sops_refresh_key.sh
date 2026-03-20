#!/bin/zsh
NO_PUSH=false
POS_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-push|-n) NO_PUSH=true ;;
        *) POS_ARGS+=("$arg") ;;
    esac
done

if [[ ${#POS_ARGS[@]} -lt 2 ]]; then
    echo "Usage: ./sops_refresh_key.sh [--no-push|-n] <ip/hostname> <flake_name>"
    exit 1
fi

HOST="${POS_ARGS[1]}"
FLAKE_NAME="${POS_ARGS[2]}"

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
    echo "Added new &hosts_$FLAKE_NAME key to .sops.yaml"
fi

SECRETS_FILE="hosts/$FLAKE_NAME/secrets.yaml"
if [[ -f "$SECRETS_FILE" ]]; then
    echo "Re-encrypting $SECRETS_FILE with the updated keys..."
    sops updatekeys -y "$SECRETS_FILE"
else
    echo "No secrets file found at $SECRETS_FILE to re-encrypt."
fi

if [[ "$NO_PUSH" == true ]]; then
    echo "Not pushing because of --no-push."
else
    git add .sops.yaml
    [[ -f "$SECRETS_FILE" ]] && git add "$SECRETS_FILE"

    if ! git diff --cached --quiet; then
        COMMIT_MSG="Update sops keys for $FLAKE_NAME - $(date +'%Y-%m-%d %H:%M:%S')"
        git commit -m "$COMMIT_MSG"
        git push --quiet
    else
        echo "No changes to commit."
    fi
fi