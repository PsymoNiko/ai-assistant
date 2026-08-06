#!/usr/bin/env bash
# create_docker_secrets.sh
# Create Docker secrets (Swarm) from sample files under projects/litellm/secrets
# This script requires Docker Swarm mode for docker secret create to work.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_DIR="$ROOT_DIR/projects/litellm/secrets"

if [ ! -d "$SECRETS_DIR" ]; then
  echo "Secrets directory $SECRETS_DIR does not exist. Create it and place secret files: litellm_master_key.txt, litellm_salt_key.txt, litellm_api_key.txt"
  exit 1
fi

if ! docker info 2>/dev/null | grep -q 'Swarm: active'; then
  echo "Docker Swarm is not active. Initialize Swarm with 'docker swarm init' or use the docker-compose.secrets.yml pattern for local secrets."
  exit 1
fi

declare -A mapping=(
  [litellm_master_key]="litellm_master_key.txt"
  [litellm_salt_key]="litellm_salt_key.txt"
  [litellm_api_key]="litellm_api_key.txt"
)

for secret in "${!mapping[@]}"; do
  file="$SECRETS_DIR/${mapping[$secret]}"
  if [ ! -f "$file" ]; then
    echo "Missing secret file: $file — create it with the desired secret value"
    continue
  fi

  # If a secret with the same name exists, remove it first (prompt)
  if docker secret ls --format '{{.Name}}' | grep -q "^$secret$"; then
    echo "Docker secret $secret already exists. Overwrite? (y/N)"
    read -rn1 answer
    echo
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      docker secret rm "$secret"
    else
      echo "Skipping $secret"
      continue
    fi
  fi

  docker secret create "$secret" "$file"
  echo "Created docker secret $secret from $file"
done
