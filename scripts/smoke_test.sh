#!/usr/bin/env bash
# smoke_test.sh
# Run a set of basic smoke-tests against the gateway and LiteLLM endpoints.

set -euo pipefail
GATEWAY=${1:-http://localhost:8080}

echo "Testing gateway /ai-gateway (forward to n8n)..."
curl -sS -X POST "$GATEWAY/ai-gateway" -H "Content-Type: application/json" -d '{"text":"smoke test from script"}' || echo "ai-gateway test failed"

echo
echo "Testing gateway direct LLM call (/call-litellm)..."
curl -sS -X POST "$GATEWAY/call-litellm" -H "Content-Type: application/json" -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hello from smoke test"}]}' || echo "call-litellm test failed"

echo
echo "Smoke tests completed. Review responses above for errors."
