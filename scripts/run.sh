#!/usr/bin/env bash
# run.sh - orchestrator script to perform setup tasks for the ai-assistant project
# Usage:
#   ./scripts/run.sh all        # run all tasks (A, B, C, D)
#   ./scripts/run.sh A          # run only task A
#   ./scripts/run.sh B          # run only task B
#   ./scripts/run.sh C          # run only task C
#   ./scripts/run.sh D          # run only task D
# If no argument provided, the script will prompt for a choice.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TASK=${1:-}

usage() {
  cat <<EOF
Usage: $0 [all|A|B|C|D]
A: Create LiteLLM virtual key and write to projects/litellm/.env
B: Ensure gateway attaches Authorization header when calling LiteLLM (code already patched)
C: Create n8n credential template and update Planner workflow to reference env-based Authorization header
D: Convert LiteLLM compose to use Docker secrets (create sample secret files)
all: run A then B then C then D
EOF
}

if [ -z "$TASK" ]; then
  echo "No task specified. Choose one: all, A, B, C, D"
  read -rp "Task: " TASK
fi

run_A() {
  echo "Running Task A: create LiteLLM virtual key (helper)"
  bash scripts/create_litellm_key.sh || { echo "create_litellm_key.sh failed or needs manual intervention"; return 1; }
}

run_B() {
  echo "Running Task B: gateway patch is already applied in src/backend/gateway/app/main.py"
  echo "Ensure you set LITELLM_API_KEY in the gateway environment and restart the gateway container."
}

run_C() {
  echo "Running Task C: n8n credential guidance and workflow update"
  echo "Planner workflow has been updated to reference Authorization=Bearer <env LITELLM_API_KEY>.
  Please import workflows/02-planner.json into your n8n instance and create an n8n credential named 'LiteLLM API' if you prefer UI-managed credentials."
}

run_D() {
  echo "Running Task D: create Docker secrets sample files for LiteLLM"
  mkdir -p projects/litellm/secrets
  if [ ! -f projects/litellm/secrets/litellm_master_key.txt.sample ]; then
    cat > projects/litellm/secrets/litellm_master_key.txt.sample <<EOF
REPLACE_WITH_STRONG_MASTER_KEY
EOF
  fi
  if [ ! -f projects/litellm/secrets/litellm_salt_key.txt.sample ]; then
    cat > projects/litellm/secrets/litellm_salt_key.txt.sample <<EOF
REPLACE_WITH_STRONG_SALT_KEY
EOF
  fi
  if [ ! -f projects/litellm/secrets/litellm_api_key.txt.sample ]; then
    cat > projects/litellm/secrets/litellm_api_key.txt.sample <<EOF
REPLACE_WITH_VIRTUAL_API_KEY
EOF
  fi
  echo "Sample secret files created under projects/litellm/secrets/."
  echo "If running Docker Swarm you can create secrets with:"
  echo "  docker secret create litellm_master_key projects/litellm/secrets/litellm_master_key.txt.sample"
}

case "$TASK" in
  all|ALL)
    run_A
    run_B
    run_C
    run_D
    ;;
  A|a)
    run_A
    ;;
  B|b)
    run_B
    ;;
  C|c)
    run_C
    ;;
  D|d)
    run_D
    ;;
  *)
    usage
    exit 1
    ;;
esac

echo "Done."
