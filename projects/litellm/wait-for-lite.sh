#!/usr/bin/env bash
# Helper script: wait-for-lite.sh
# Poll the LiteLLM health endpoint until it responds or a timeout is reached.

HOST=${1:-"http://localhost:4000/health"}
TIMEOUT=${2:-60}

start=$(date +%s)
while true; do
  if curl -fsS "$HOST" >/dev/null 2>&1; then
    echo "LiteLLM is healthy at $HOST"
    exit 0
  fi
  now=$(date +%s)
  if [ $((now - start)) -ge $TIMEOUT ]; then
    echo "Timed out waiting for LiteLLM at $HOST"
    exit 1
  fi
  sleep 2
done
