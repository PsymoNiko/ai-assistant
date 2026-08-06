#!/usr/bin/env bash
# create_litellm_key.sh
# Helper that attempts to create a LiteLLM virtual API key via the admin endpoint and writes it to projects/litellm/.env

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/projects/litellm/.env"
LITELLM_URL=${LITELLM_URL:-http://localhost:4000}
ADMIN_TOKEN=${LITELLM_ADMIN_TOKEN:-}

if [ -z "$ADMIN_TOKEN" ]; then
  echo "LITELLM_ADMIN_TOKEN not set. Set it in the environment to call admin endpoints, or create a key manually."
  exit 1
fi

read -rp "Enter name for new virtual key [n8n-integration]: " KEY_NAME
KEY_NAME=${KEY_NAME:-n8n-integration}

resp=$(curl -sS -X POST "$LITELLM_URL/v1/keys" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{ \"name\": \"$KEY_NAME\", \"scopes\": [\"chat:read\",\"chat:write\"] }")

if echo "$resp" | grep -q "key"; then
  # Try to parse key using jq if available
  if command -v jq >/dev/null 2>&1; then
    NEW_KEY=$(echo "$resp" | jq -r '.key // .api_key // .value') || true
  else
    NEW_KEY=$(echo "$resp" | sed -n 's/.*\"key\":\s*\"\([^\"]*\)\".*/\1/p') || true
  fi

  if [ -z "$NEW_KEY" ]; then
    echo "Unable to extract the key from the response. Response was:" >&2
    echo "$resp" >&2
    exit 1
  fi

  echo "Created key: $NEW_KEY"

  # Write or update .env
  mkdir -p "$(dirname "$ENV_FILE")"
  if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<EOF
LITELLM_MASTER_KEY=REPLACE_ME
LITELLM_SALT_KEY=REPLACE_ME
DATABASE_URL=postgresql://litellm:litellm@db:5432/litellm
LITELLM_API_KEY="$NEW_KEY"
EOF
    echo ".env created at $ENV_FILE with the new API key (please replace placeholders for other secrets)."
  else
    # replace or append LITELLM_API_KEY
    if grep -q "^LITELLM_API_KEY" "$ENV_FILE"; then
      sed -i.bak "s|^LITELLM_API_KEY=.*|LITELLM_API_KEY=\"$NEW_KEY\"|" "$ENV_FILE"
    else
      echo "LITELLM_API_KEY=\"$NEW_KEY\"" >> "$ENV_FILE"
    fi
    echo "Updated $ENV_FILE with new LITELLM_API_KEY"
  fi

else
  echo "Failed to create key. Response was:" >&2
  echo "$resp" >&2
  exit 1
fi
