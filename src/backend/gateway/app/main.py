from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
import httpx
import os

app = FastAPI(title="AI Assistant Gateway")

# Config
N8N_WEBHOOK_URL = os.environ.get("N8N_WEBHOOK_URL", "http://n8n:5678/webhook/ai-gateway")
LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm:4000/v1/chat/completions")

@app.post("/ai-gateway")
async def ai_gateway(request: Request):
    """Receive incoming assistant requests from clients and forward to the Planner.

    The gateway currently forwards the request payload to the n8n webhook used by the Planner workflow.
    """
    payload = await request.json()

    # Basic validation
    if not payload:
        return JSONResponse({"error": "empty payload"}, status_code=400)

    # Forward to n8n webhook (planner)
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.post(N8N_WEBHOOK_URL, json=payload)
            return JSONResponse(content=resp.json(), status_code=resp.status_code)
        except httpx.RequestError as e:
            return JSONResponse({"error": "failed to contact planner", "detail": str(e)}, status_code=502)

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
