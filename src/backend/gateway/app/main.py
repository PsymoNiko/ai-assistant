from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
import httpx
import os
from typing import Optional

app = FastAPI(title="AI Assistant Gateway")

# Config
N8N_WEBHOOK_URL = os.environ.get("N8N_WEBHOOK_URL", "http://n8n:5678/webhook/ai-gateway")
LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm:4000/v1/chat/completions")
LITELLM_API_KEY = os.environ.get("LITELLM_API_KEY")


@app.post("/ai-gateway")
async def ai_gateway(request: Request):
    """Receive incoming assistant requests from clients and either forward to the Planner (n8n)
    or optionally call the LLM directly when the payload sets `direct_llm: true`.

    Behavior:
    - If payload contains `direct_llm: true` the gateway will POST to the configured LITELLM_URL
      and include Authorization: Bearer <LITELLM_API_KEY> when available.
    - Otherwise the request is forwarded to the n8n webhook defined by N8N_WEBHOOK_URL.
    """
    payload = await request.json()

    if not payload:
        return JSONResponse({"error": "empty payload"}, status_code=400)

    # If the client requested a direct LLM call, call LITELLM_URL with Authorization header
    if payload.get("direct_llm"):
        headers = {"Content-Type": "application/json"}
        if LITELLM_API_KEY:
            headers["Authorization"] = f"Bearer {LITELLM_API_KEY}"

        async with httpx.AsyncClient(timeout=120.0) as client:
            try:
                resp = await client.post(LITELLM_URL, json=payload.get("llm_body", payload), headers=headers)
                # Try to return the JSON body if available, otherwise raw text
                try:
                    return JSONResponse(content=resp.json(), status_code=resp.status_code)
                except Exception:
                    return JSONResponse(content={"text": resp.text}, status_code=resp.status_code)
            except httpx.RequestError as e:
                return JSONResponse({"error": "failed to contact liteLLM", "detail": str(e)}, status_code=502)

    # Default behavior: forward to n8n Planner webhook
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.post(N8N_WEBHOOK_URL, json=payload)
            try:
                return JSONResponse(content=resp.json(), status_code=resp.status_code)
            except Exception:
                return JSONResponse(content={"text": resp.text}, status_code=resp.status_code)
        except httpx.RequestError as e:
            return JSONResponse({"error": "failed to contact planner", "detail": str(e)}, status_code=502)


@app.post("/call-litellm")
async def call_litellm(body: dict):
    """Explicit endpoint to call the configured LiteLLM instance directly.

    Expects a JSON body compatible with your LiteLLM API (chat/completions style). The gateway
    will attach Authorization: Bearer <LITELLM_API_KEY> when available.
    """
    if not body:
        return JSONResponse({"error": "empty body"}, status_code=400)

    headers = {"Content-Type": "application/json"}
    if LITELLM_API_KEY:
        headers["Authorization"] = f"Bearer {LITELLM_API_KEY}"

    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            resp = await client.post(LITELLM_URL, json=body, headers=headers)
            try:
                return JSONResponse(content=resp.json(), status_code=resp.status_code)
            except Exception:
                return JSONResponse(content={"text": resp.text}, status_code=resp.status_code)
        except httpx.RequestError as e:
            return JSONResponse({"error": "failed to contact liteLLM", "detail": str(e)}, status_code=502)


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            data = await ws.receive_json()
            # Echo back or forward to planner via HTTP in a real implementation
            await ws.send_json({"received": data})
    except WebSocketDisconnect:
        return
