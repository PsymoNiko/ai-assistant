#!/usr/bin/env bash
# rotate_secrets.sh (interactive guidance)
# This script does not rotate remotely for you; it guides and optionally replaces local placeholders.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "WARNING: This helper will *not* rotate tokens on external services automatically."
echo "It will help you identify files to update and optionally replace local placeholders."

# Files to check
FILES=(
  "$ROOT_DIR/projects/litellm/.env"
  "$ROOT_DIR/n8n/.env"
  "$ROOT_DIR/secret.txt"
)

echo "The script will show the following local files if they exist and prompt you to edit them manually."
for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    echo " - $f"
  fi
done

echo
read -rp "Have you rotated external tokens on their provider consoles (n8n, Litellm, HuggingFace, etc.)? (y/N) " ok
if [[ "$ok" =~ ^[Yy]$ ]]; then
  echo "Great. Now update local files (.env, secret files) with the new tokens."
else
  echo "Please rotate the tokens in the provider UIs now (this script cannot do that for you)."
fi

echo "If you want, open the projects/litellm/.env file to paste the new LITELLM_API_KEY now."
read -rp "Open projects/litellm/.env in your editor? (y/N) " edit
if [[ "$edit" =~ ^[Yy]$ ]]; then
  ${EDITOR:-vi} "$ROOT_DIR/projects/litellm/.env"
fi

echo "Finished guidance. Remember to restart containers after updating local .env or secrets."
