#!/usr/bin/env bash
# setup_env_and_network.sh
# Create Docker network (management_network) and copy .env examples into place.
# Usage: ./scripts/setup_env_and_network.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 1) Create Docker network if not exists
NETWORK_NAME=${1:-management_network}
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
  echo "Creating docker network ${NETWORK_NAME}..."
  docker network create "${NETWORK_NAME}"
else
  echo "Docker network ${NETWORK_NAME} already exists."
fi

# 2) Ensure projects/litellm/.env exists
LITELLM_ENV_SAMPLE="$ROOT_DIR/projects/litellm/.env.example"
LITELLM_ENV="$ROOT_DIR/projects/litellm/.env"
if [ -f "$LITELLM_ENV_SAMPLE" ] && [ ! -f "$LITELLM_ENV" ]; then
  echo "Copying LiteLLM .env example to projects/litellm/.env"
  cp "$LITELLM_ENV_SAMPLE" "$LITELLM_ENV"
  echo "Please open $LITELLM_ENV and fill secure values (LITELLM_MASTER_KEY, LITELLM_SALT_KEY, LITELLM_API_KEY)."
else
  echo "LiteLLM .env already exists or sample missing."
fi

# 3) Ensure projects/litellm/secrets sample files exist
if [ ! -d "$ROOT_DIR/projects/litellm/secrets" ]; then
  mkdir -p "$ROOT_DIR/projects/litellm/secrets"
  cp "$ROOT_DIR/projects/litellm/secrets"/*.sample "$ROOT_DIR/projects/litellm/secrets/" 2>/dev/null || true
fi

echo "Setup done. Edit any .env or secret sample files before starting services."
