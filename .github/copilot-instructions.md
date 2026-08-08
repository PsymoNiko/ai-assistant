# Copilot Instructions for ai-assistant Repository

This document provides essential guidance for AI assistants working in the ai-assistant codebase. It captures architectural decisions, key conventions, and operational commands needed to work effectively across the repository.

---

## 📐 High-Level Architecture

The AI Assistant is a **modular, microservices-based platform** designed to be an operational AI agent (not just a chatbot). It enables users to interact with infrastructure, monitoring, and services using natural language.

### Core System Flow

```
User Input (Web/CLI/Voice)
    ↓
FastAPI Gateway (src/backend/gateway/)
    ↓
n8n Workflow Engine (workflows/*.json)
    ├─→ Intent parsing & tool selection via LLM
    ├─→ Tool execution (Zabbix API, SSH, Docker, etc.)
    └─→ Result aggregation & response formatting
    ↓
LiteLLM (LLM provider proxy)
    ↓
llama-server (Local inference)
    ↓
GGUF Model (Quantized local model)
```

### Key Architectural Principles

1. **Model as Decision-Maker, Not Executor**: The LLM identifies intent and selects tools; actual execution happens through controlled, auditable interfaces (Zabbix API, SSH gateway, etc.). Never grant the LLM direct shell access.

2. **Layered Tool Architecture**:
   - **Policy Layer**: RBAC, approval rules, risk controls
   - **Tool Definition Layer**: Explicit, limited tool set (e.g., `docker_ps`, `check_service`, not raw shell commands)
   - **Executor Layer**: Zabbix API, SSH gateway, or other service integrations
   - **Audit Layer**: Logs user, timestamp, command, and result

3. **Workflow-Centric Orchestration**: n8n workflows define the sequence of operations, LLM decisions, data transformations, and API calls. Workflows are the "source of truth" for multi-step processes.

---

## 🏗️ Repository Structure & Key Directories

```
src/
├── backend/
│   ├── gateway/           # FastAPI entry point (active)
│   │   ├── main.py        # FastAPI app with /ai-gateway, /call-litellm, /ws endpoints
│   │   ├── requirements.txt
│   │   └── Dockerfile     # Python 3.11 slim-based
│   ├── [future: api/, core/, adapters/, storage/, services/]
│   └── README.md
└── frontend/              # Frontend placeholder

workflows/
├── 01-ai-gateway.json     # Webhook entry, request routing
├── 02-planner.json        # Request parsing, tool selection
├── 03-memory-retrieval.json
└── 04-mcp-dispatcher.json

sdk/js/                    # JavaScript/TypeScript SDK

infra/
├── monitoring/            # Prometheus + Grafana configs
│   ├── prometheus/alerts.yml
│   ├── grafana/dashboards/
│   └── docker-compose.monitoring.yml
└── README.md

projects/litellm/          # LiteLLM configuration
├── .env.example           # Template for secrets (master key, salt key, DB URL, API key)
└── docker-compose.secrets.yml

scripts/                   # Operational helpers
├── run.sh                 # Main orchestrator (tasks A, B, C, D)
├── create_litellm_key.sh
├── setup_env_and_network.sh
├── zabbix_client.py       # Zabbix JSON-RPC client
└── [other utilities]

tests/                     # Test suite (placeholder structure)

docs/                      # Documentation

examples/                  # Demo and reference applications

docker-compose.yml         # Main local stack (Gateway, n8n, Postgres, Redis, Qdrant, MinIO, LiteLLM)
ROADMAP.md                 # Project milestones (Milestone 0 complete, Milestone 1 in progress)
README.md                  # Comprehensive architecture guide (comprehensive, in Persian/English)
STRUCTURE.md               # Repository layout guide
```

---

## 🛠️ Build, Test & Deployment Commands

### Docker Compose (Local Development Stack)

```bash
# Start all services (Gateway + n8n + Postgres + Redis + Qdrant + MinIO + LiteLLM)
docker-compose up

# Start in background
docker-compose up -d

# Stop all services
docker-compose down

# Rebuild images
docker-compose up --build
```

**Services & Ports:**
- Gateway: `http://localhost:8080`
- n8n: `http://localhost:5678`
- Postgres: `localhost:5432`
- Redis: `localhost:6379`
- Qdrant: `http://localhost:6333`
- MinIO: `http://localhost:9000` (creds: minio/minio123)
- LiteLLM: `http://localhost:4000/v1/chat/completions`

### FastAPI Gateway (Backend)

```bash
# Development server (watch mode)
cd src/backend/gateway
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080

# Production server
uvicorn app.main:app --host 0.0.0.0 --port 8080 --workers 4

# Test the gateway
curl -X POST http://localhost:8080/ai-gateway \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}'

# Test WebSocket
# See src/backend/gateway/app/main.py for WS endpoint /ws
```

### Testing

No centralized test runner currently exists. Tests are organized in `tests/` (structure: unit/, integration/, e2e/).

```bash
# When tests are added, expect pytest:
pytest tests/unit/          # Run unit tests
pytest tests/integration/   # Run integration tests
pytest tests/               # Run all tests
pytest -v tests/            # Verbose output
pytest tests/ -k "test_gateway"  # Run specific test pattern
```

### LiteLLM Setup

LiteLLM acts as an adapter between n8n/clients and the local llama-server model.

```bash
# Copy env template and configure
cp projects/litellm/.env.example projects/litellm/.env

# Edit .env with:
# LITELLM_MASTER_KEY=<strong-random-value>
# LITELLM_SALT_KEY=<strong-random-value>
# DATABASE_URL=postgresql://...
# LITELLM_API_KEY=<service-api-key>

# Create/rotate keys (scripts/create_litellm_key.sh)
bash scripts/create_litellm_key.sh
```

### Setup Scripts

Operational helpers in `scripts/`:

```bash
# Main orchestrator: setup and deployment
bash scripts/run.sh [all|A|B|C|D]
  # A: Create LiteLLM virtual key
  # B: Create Docker Compose secrets
  # C: Import n8n workflows
  # D: Setup env and network

# Network setup
bash scripts/setup_env_and_network.sh

# Smoke test (verify services are accessible)
bash scripts/smoke_test.sh

# Secret management
bash scripts/create_docker_secrets.sh
bash scripts/rotate_secrets.sh

# Workflow import
bash scripts/import_n8n_workflows.sh
```

### n8n Workflows

Workflows are JSON definitions in `workflows/`. They define the orchestration logic:

- **01-ai-gateway.json**: Webhook trigger, request routing
- **02-planner.json**: LLM-based request parsing and tool selection
- **03-memory-retrieval.json**: RAG/context retrieval from Qdrant
- **04-mcp-dispatcher.json**: MCP-based tool execution dispatch

Workflows can be:
- Edited visually in n8n UI: http://localhost:5678
- Exported/imported via scripts/import_n8n_workflows.sh
- Committed as JSON to version control

---

## 📋 Key Conventions & Patterns

### 1. FastAPI Gateway Patterns

**Location:** `src/backend/gateway/app/main.py`

**Key Endpoints:**
- `POST /ai-gateway` — Main entry point. Forwards to n8n Planner by default; if payload has `direct_llm: true`, routes to LiteLLM directly.
- `POST /call-litellm` — Explicit endpoint for direct LLM calls (OpenAI-compatible format).
- `WS /ws` — WebSocket for real-time streaming and interactive communication.

**Environment Variables:**
- `N8N_WEBHOOK_URL` — Points to n8n Planner (default: `http://n8n:5678/webhook/ai-gateway`)
- `LITELLM_URL` — Points to LiteLLM endpoint (default: `http://litellm:4000/v1/chat/completions`)
- `LITELLM_API_KEY` — Optional auth header for LiteLLM

**Pattern: Flexible Routing**
```python
# If direct_llm flag, bypass n8n; otherwise use planner
if payload.get("direct_llm"):
    # Call LiteLLM directly
else:
    # Forward to n8n Planner webhook
```

### 2. n8n Workflow Conventions

**Workflow Structure:**
1. **Trigger** (Webhook, scheduled, etc.)
2. **Extract/Validate** (Set, function, or conditional node)
3. **LLM Call** (n8n OpenAI/LiteLLM node)
4. **Tool Selection** (Conditional logic based on LLM response)
5. **Execute Tool** (Zabbix API, SSH, Docker, etc.)
6. **Transform Response** (Function, Set, or LLM summary)
7. **Return** (Respond to webhook or format for client)

**LLM Integration Pattern in n8n:**
- Use n8n's built-in OpenAI node, configured to point to LiteLLM endpoint
- Set model name (e.g., "local-llama") and base URL to LiteLLM
- Include API key from `projects/litellm/.env`

### 3. Tool Definition & Auditing

**Expected Pattern (not yet fully implemented):**
```python
# Define allowed tools explicitly
ALLOWED_TOOLS = {
    'docker_ps': {'allowed_hosts': ['*'], 'readonly': True},
    'check_service': {'allowed_hosts': ['production', 'staging'], 'readonly': True},
    'zabbix_get_host': {'allowed_hosts': ['*'], 'readonly': True},
    # 'exec_shell': forbidden; too dangerous
}

# When LLM selects a tool, verify policy
if tool not in ALLOWED_TOOLS:
    raise ToolNotAllowed(tool)
```

Audit all tool executions: log user, timestamp, tool name, parameters, and result.

### 4. Zabbix Integration

**Zabbix Client:** `scripts/zabbix_client.py`

A reusable JSON-RPC client for Zabbix API v5/6/7. Supports:
- `host_get()` — List hosts
- `item_get()` — Fetch items/metrics
- `event_get()` — Retrieve events
- Custom methods via `request(method, params)`

**Usage Pattern in Workflows:**
```javascript
// In n8n HTTP node, call Zabbix API
POST https://zabbix.example.com/api_jsonrpc.php
{
  "jsonrpc": "2.0",
  "method": "host.get",
  "params": { "output": ["hostid", "host", "name"] },
  "auth": "<zabbix-token>",
  "id": 1
}
```

### 5. SSH Tool Pattern

**Pattern (in workflows):**
1. LLM identifies SSH command needed (e.g., `docker_ps`, `check_disk`)
2. Workflow maps to a predefined SSH script or restricted command
3. Execute via SSH gateway with:
   - Source IP/user verification
   - Command allowlist checking
   - Result capture and return
4. Never exec raw user input as shell commands

### 6. Local Model (llama-server) Integration

**Model Inference Stack:**
- **Model Format:** GGUF (quantized, CPU-optimized)
- **Runner:** `llama-server` (part of llama.cpp project)
- **Adapter:** LiteLLM (provides OpenAI-compatible API)
- **Endpoint:** LiteLLM exposes `POST /v1/chat/completions`

**Hardware Constraints:**
- No GPU
- ~40 CPU cores total; max ~30 cores for inference
- 32GB RAM
- Model size limit: ~20GB (quantized models like gemma-3-12b-it-Q4_K_M)

**Model Selection:**
- **Recommended for CPU:** gemma-3-12b-it-Q4_K_M.gguf (smaller, faster, adequate quality)
- **Available:** gemma-4-E2B-it-Q4_K_M.gguf, gemma-2-27b-it-Q5_K_M.gguf (heavy)

**Request Format (OpenAI-compatible):**
```json
{
  "model": "local-llama",
  "messages": [{"role": "user", "content": "..."}],
  "temperature": 0.7,
  "max_tokens": 1024
}
```

### 7. Environment & Secrets Management

**Convention:**
- All secrets go in `projects/litellm/.env` (generated from `.env.example`)
- Secrets **never** hardcoded in Python, JSON, or committed to git
- Use Docker secrets for compose (via `create_docker_secrets.sh`)
- Rotate secrets periodically (`rotate_secrets.sh`)

**Required Env Vars (Gateway):**
```bash
N8N_WEBHOOK_URL=http://n8n:5678/webhook/ai-gateway
LITELLM_URL=http://litellm:4000/v1/chat/completions
LITELLM_API_KEY=<secret-key>
```

---

## 🎯 Development Workflow

### When Adding a New Feature

1. **Determine the Layer:**
   - LLM reasoning? → Modify workflow in `workflows/02-planner.json`
   - New endpoint? → Add to `src/backend/gateway/app/main.py`
   - New integration (Zabbix, SSH, etc.)? → Create n8n node or Python script in `scripts/` or `src/backend/`
   - UI/SDK? → Work in `sdk/js/` or `src/frontend/`

2. **Follow the Architecture:**
   - Request enters via FastAPI Gateway
   - Gets routed to n8n Planner workflow
   - Planner calls LLM to determine tool
   - Workflow executes tool, transforms result, returns via gateway
   - Optionally stream via WebSocket

3. **Test Locally:**
   ```bash
   docker-compose up
   curl -X POST http://localhost:8080/ai-gateway \
     -H "Content-Type: application/json" \
     -d '{"message": "...", "user_id": "test"}'
   ```

4. **Add Tests:**
   - Unit tests in `tests/unit/`
   - Integration tests in `tests/integration/` (with docker-compose)
   - End-to-end tests in `tests/e2e/`

5. **Update Workflows (if needed):**
   - Edit in n8n UI or JSON directly
   - Test via n8n dev server
   - Export and commit to `workflows/`

### Debugging

- **FastAPI app errors:** Check logs in `docker-compose logs gateway`
- **n8n workflow issues:** Use n8n UI at http://localhost:5678 to inspect nodes and execution logs
- **LiteLLM/Model issues:** Check `docker-compose logs litellm`
- **Zabbix connectivity:** Test with `scripts/zabbix_client.py`
- **WebSocket debugging:** Use Chrome DevTools or `wscat` CLI tool

---

## 📚 Key Files to Understand First

| File | Purpose | Key Pattern |
|------|---------|-----------|
| `src/backend/gateway/app/main.py` | FastAPI entry point | Direct LLM vs. planner routing |
| `workflows/02-planner.json` | Main orchestration logic | LLM → tool selection → execution |
| `docker-compose.yml` | Local stack definition | Service configuration and networking |
| `README.md` | Comprehensive architecture guide | Full system design (extensive, in Persian) |
| `ROADMAP.md` | Project milestones | Current status: Milestone 0 done, Milestone 1 in progress |
| `scripts/zabbix_client.py` | Zabbix integration example | JSON-RPC client pattern |
| `scripts/run.sh` | Operational orchestration | Setup and deployment helper |

---

## 🚀 Milestones & Feature Status

**Milestone 0 (Complete):**
- ✅ Repository scaffolding, docs, issue templates
- ✅ Basic CI infrastructure
- ✅ Docker Compose setup

**Milestone 1 (In Progress):**
- ✅ FastAPI Gateway
- ✅ n8n Workflow Engine
- ✅ LiteLLM + llama-server integration
- ⏳ Demo/example application
- ⏳ End-to-end tests
- ⏳ API documentation

**Future (Milestone 2+):**
- Plugin system & extensibility
- RAG (Qdrant integration)
- Long-term memory
- Voice assistant (Whisper + Piper)
- Production hardening & scaling
- Kubernetes deployment

---

## 🔐 Security & Best Practices

1. **Never let LLM execute raw shell commands.** Always route through tool abstractions.
2. **Use RBAC.** Define what each user/service can do (viewer, operator, admin).
3. **Audit everything.** Log tool calls: user, timestamp, tool, params, result.
4. **Secrets management.** Rotate keys regularly; use Docker secrets in production.
5. **SSH Access.** Use an SSH gateway layer; never expose SSH directly to workflow engine.
6. **Zabbix API:** Use read-only operations by default; require approval for write operations.

---

## 📖 Additional Resources

- **README.md** — Comprehensive system design and architecture (read sections on n8n, LiteLLM, Zabbix, SSH, Voice)
- **ROADMAP.md** — Project milestones and strategic direction
- **STRUCTURE.md** — Repository layout and future component organization
- **n8n Documentation** — https://docs.n8n.io
- **LiteLLM Docs** — https://docs.litellm.ai
- **Zabbix API Docs** — https://www.zabbix.com/documentation/current/en/manual/api
- **FastAPI** — https://fastapi.tiangolo.com

---

**Last Updated:** 2026-08-08  
**Repository:** gave-partake-unwed/ai-assistant  
**Current State:** Milestone 1 (MVP) in active development
