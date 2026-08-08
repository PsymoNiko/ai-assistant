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
