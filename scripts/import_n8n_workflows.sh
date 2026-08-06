#!/usr/bin/env bash
# import_n8n_workflows.sh
# Import workflows/*.json into an n8n instance via the REST import endpoint.
# Requires N8N_URL and either N8N_API_KEY or N8N_BASIC_AUTH credentials depending on your n8n setup.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
N8N_URL=${N8N_URL:-http://localhost:5678}
# Optionally provide an API token or Basic auth user:pass
N8N_API_KEY=${N8N_API_KEY:-}
N8N_BASIC_AUTH=${N8N_BASIC_AUTH:-}

if [ -z "$N8N_API_KEY" ] && [ -z "$N8N_BASIC_AUTH" ]; then
  echo "Set N8N_API_KEY or N8N_BASIC_AUTH in the environment before running this script."
  echo "Example: export N8N_API_KEY=... OR export N8N_BASIC_AUTH=user:password"
  exit 1
fi

for wf in "$ROOT_DIR"/workflows/*.json; do
  echo "Importing $wf..."
  if [ -n "$N8N_API_KEY" ]; then
    curl -sS -X POST "$N8N_URL/workflows/import" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $N8N_API_KEY" \
      --data-binary "@$wf" | jq '.' || true
  else
    # Basic auth
    curl -sS -X POST "$N8N_URL/workflows/import" \
      -u "$N8N_BASIC_AUTH" \
      -H "Content-Type: application/json" \
      --data-binary "@$wf" | jq '.' || true
  fi
  echo
done

echo "Workflow import complete. If any imports failed, inspect the output above."
