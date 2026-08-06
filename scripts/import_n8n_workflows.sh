#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
N8N_URL=${N8N_URL:-http://localhost:5678}
N8N_API_KEY=${N8N_API_KEY:-}
N8N_BASIC_AUTH=${N8N_BASIC_AUTH:-}

if [ -z "$N8N_API_KEY" ] && [ -z "$N8N_BASIC_AUTH" ]; then
  echo "Set N8N_API_KEY or N8N_BASIC_AUTH in the environment before running this script."
  echo "Example: export N8N_API_KEY=... OR export N8N_BASIC_AUTH=user:password"
  exit 1
fi

# n8n's API import endpoint uses /rest/workflows/import on most installations
IMPORT_PATH="/rest/workflows/import"

for wf in "$ROOT_DIR"/workflows/*.json; do
  echo "Importing $wf..."
  resp_file=$(mktemp)
  http_status="000"

  if [ -n "$N8N_API_KEY" ]; then
    http_status=$(curl -sS -o "$resp_file" -w "%{http_code}" -X POST "$N8N_URL${IMPORT_PATH}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $N8N_API_KEY" \
      --data-binary "@$wf" || echo "000")
  else
    http_status=$(curl -sS -o "$resp_file" -w "%{http_code}" -X POST "$N8N_URL${IMPORT_PATH}" \
      -u "$N8N_BASIC_AUTH" \
      -H "Content-Type: application/json" \
      --data-binary "@$wf" || echo "000")
  fi

  echo "HTTP status: $http_status"
  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    if command -v jq >/dev/null 2>&1; then
      cat "$resp_file" | jq . || ( echo "Response not valid JSON:"; sed -n '1,200p' "$resp_file" )
    else
      echo "Response:"; sed -n '1,200p' "$resp_file"
    fi
  else
    echo "Import failed or returned non-2xx. Raw response:"; sed -n '1,200p' "$resp_file"
  fi

  rm -f "$resp_file"
  echo
done
