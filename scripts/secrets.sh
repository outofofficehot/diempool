#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/../secrets.yaml"

# Age key location
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

get_secret() {
    local key="$1"
    sops -d --extract "[\"$key\"]" "$SECRETS_FILE" 2>/dev/null
}

case "${1:-}" in
    get)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 get <key>" >&2
            exit 1
        fi
        get_secret "$2"
        ;;
    list)
        sops -d "$SECRETS_FILE" | grep -E '^[a-z_]+:' | cut -d: -f1
        ;;
    *)
        echo "Usage: $0 {get|list} [key]" >&2
        exit 1
        ;;
esac
