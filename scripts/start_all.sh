#!/usr/bin/env bash
# start_all.sh
# Bring up the core stack in the recommended order.
# Usage: ./scripts/start_all.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "Starting LiteLLM (projects/litellm)..."
docker compose -f projects/litellm/docker-compose.yml --env-file projects/litellm/.env up -d

echo "Waiting for LiteLLM health endpoint..."
bash projects/litellm/wait-for-lite.sh http://localhost:4000/health 120 || {
  echo "LiteLLM did not become healthy in time. Check logs with: docker compose -f projects/litellm/docker-compose.yml logs litellm --tail 200"
}

echo "Starting core repo-wide compose (gateway, n8n, postgres, qdrant, minio, litellm if present)..."
docker compose up -d

echo "Starting monitoring stack (optional)..."
docker compose -f infra/monitoring/docker-compose.monitoring.yml up -d || echo "Monitoring stack failed to start; ensure prerequisites are met."

echo "All services started. Use 'docker compose ps' to inspect running containers."
