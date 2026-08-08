02 Planner (Complete) — README

Purpose:
This folder contains n8n workflow exports used by the ai-assistant gateway. The 02-planner-complete.json file is a full-featured planner workflow that:
- Accepts webhook requests (POST /webhook/ai-planner)
- Calls memory retrieval (03-memory-retrieval.json)
- Builds a structured prompt instructing the LLM to return parseable JSON with keys: action, tool, reply
- Calls LiteLLM (HTTP node)
- Parses model output and routes by action (tool vs respond)
- On action==tool, delegates execution to 04-mcp-dispatcher via an Execute Workflow node
- Responds to the original webhook with the final result or error

Import notes:
- Import 02-planner-complete.json into n8n (Settings → Workflows → Import). Adjust webhook path and LiteLLM URL if needed.
- Ensure environment variable LITELLM_API_KEY is set for n8n credentials or update the HTTP node headers.
- 04 MCP Dispatcher should accept input under key "toolInput" and return an object that becomes the webhook response.

Safe defaults and policies:
- Planner expects the model to return structured JSON. The Parse node falls back to returning the raw text as a reply if parsing fails.
- Tool execution must be mediated by 04 MCP Dispatcher which enforces allowlists and audit logging. Do not execute raw shell commands from planner output.

Testing:
- Use curl to POST a sample payload: curl -X POST http://localhost:5678/webhook/ai-planner -H 'Content-Type: application/json' -d '{"text":"check http://example.local/health"}'
- Watch n8n execution to follow flow and inspect logs.

Change log:
- complete-1: Initial complete planner export (2026-08-08)

Single-file workflow:
- 02-planner-single.json: A standalone planner workflow that includes memory retrieval (inline expectations), the structured planner prompt, LLM invocation, parsing, routing, and a safe dispatcher for http_check and noop tools. Import this single workflow into your running n8n instance and set the webhook path (ai-planner-single). This avoids multiple dependent workflow files and is designed to run in environments where n8n is already managed outside the repo's docker-compose.
- 02-planner-single-v2.json: Enhanced standalone workflow (v2) with additional safe tools: http_port_check (host+port), dns_resolve (uses Cloudflare DNS over HTTPS), slack_alert (post to Incoming Webhook), input validation to reject unknown tools, and clearer error messages. Import path: ai-planner-single-v2.

Security notes:
- v2 validates tool names and required inputs to prevent accidental execution of arbitrary actions.
- Slack alerts post to the webhook URL provided in tool.input.webhook_url; keep webhook secret and consider using n8n credentials instead of passing it in payload.

Usage:
- Import 02-planner-single-v2.json into n8n and set environment variables LITELLM_URL and LITELLM_API_KEY as needed.
- Trigger example (http_check):
  curl -X POST http://<n8n-host>:5678/webhook/ai-planner-single-v2 -H 'Content-Type: application/json' -d '{"text":"http_check http://example.com/health"}'
- Trigger example (dns_resolve):
  curl -X POST http://<n8n-host>:5678/webhook/ai-planner-single-v2 -H 'Content-Type: application/json' -d '{"text":"dns_resolve example.com"}'
