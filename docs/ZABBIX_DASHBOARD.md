# Zabbix Dashboard Integration for ai-assistant

Complete guide for integrating Zabbix monitoring dashboards with the ai-assistant platform.

---

## Overview

This guide shows how to:
1. Create custom Zabbix dashboards for ai-assistant monitoring
2. Integrate Zabbix API with n8n workflows
3. Display real-time metrics to end users via FastAPI
4. Setup alerts and automation

---

## Prerequisites

- Zabbix Server 6.0+ (local or remote)
- Zabbix API access (API token or user credentials)
- ai-assistant running (gateway, n8n, services)
- Grafana (optional, for advanced dashboards)

---

## Part 1: Zabbix Setup

### 1. Create Zabbix API User

In Zabbix UI: **Administration → Users → Create User**

```
Username: ai-assistant
Password: STRONG_PASSWORD
User role: API role (create custom with minimal permissions)
Groups: AI Assistant Monitoring Group
```

Set API role permissions:
```
- host.get ✅
- item.get ✅
- event.get ✅
- history.get ✅
- problem.get ✅
- trigger.get ✅
- graph.get ✅
- dashboard.get ✅
```

### 2. Get API Token

```bash
# Via Zabbix UI: User settings → API tokens → Create API token
# Or via API:
curl -X POST https://zabbix.internal/api_jsonrpc.php \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {
      "username": "ai-assistant",
      "password": "STRONG_PASSWORD"
    },
    "id": 1
  }'

# Response includes "result" which is the auth token
# Store this in GitLab CI variable: ZABBIX_API_TOKEN
```

### 3. Create Host Group for AI Assistant

In Zabbix UI: **Data collection → Host groups → Create group**

```
Name: AI Assistant Infrastructure
```

Assign hosts:
- Gateway server
- n8n server
- Deployment servers
- Database/Redis servers

---

## Part 2: Dashboard Creation

### Dashboard 1: AI Assistant Health Overview

Create in Zabbix UI: **Monitoring → Dashboards → Create dashboard**

**Dashboard Name:** AI Assistant Health

**Widgets to Add:**

#### 1. Gateway Availability
```
Widget: Status of triggers
Hosts: Gateway server
Filter: Problem severity >= High
```

#### 2. n8n Workflow Status
```
Widget: Problems
Hosts: n8n server
Time period: Last 7 days
```

#### 3. Model Inference Performance
```
Widget: Graph
Item: llama-server CPU usage
Item: llama-server Memory usage
Time period: Last hour
Graph type: Line chart
```

#### 4. API Response Time
```
Widget: Simple graph
Item: Gateway HTTP response time (ms)
Threshold: 1000ms
```

#### 5. Error Rate
```
Widget: Graph
Item: Gateway errors (5xx) per minute
Time period: Last 24 hours
Aggregation: Average
```

#### 6. Deployment Status
```
Widget: Top N issues
Hosts: Dev and Prod servers
Number of items: 5
Sort by: Change time
```

### Dashboard 2: Infrastructure Resources

**Dashboard Name:** Infrastructure Capacity

**Widgets:**

#### 1. CPU Usage Gauge
```
Items: CPU usage % on each server
Hosts: All infrastructure servers
Max value: 100
Color scheme: Green → Red
```

#### 2. Memory Usage
```
Widget: Gauge
Items: Memory usage % each server
Format: Percentage
Critical: > 90%
```

#### 3. Disk Space
```
Widget: Gauge
Items: Disk usage % each volume
Paths: /data/harbor, /data/gitlab, /opt/ai-assistant
Warning: > 80%
Critical: > 95%
```

#### 4. Network I/O
```
Widget: Graph
Items: Network in/out each server
Time period: Last 7 days
Stack: Off (separate lines)
```

#### 5. Database Connections
```
Widget: Simple graph
Items: Postgres connections
Items: Redis connections
Max connections: Show threshold
```

---

## Part 3: n8n Workflow Integration

### Workflow: Fetch Zabbix Dashboard Data

Create new n8n workflow:

**Name:** Get Zabbix Dashboard Data

#### Step 1: HTTP Request to Zabbix API

```json
{
  "node": "HTTP Request",
  "method": "POST",
  "url": "https://zabbix.internal/api_jsonrpc.php",
  "headers": {
    "Content-Type": "application/json"
  },
  "body": {
    "jsonrpc": "2.0",
    "method": "problem.get",
    "params": {
      "selectHosts": "extend",
      "filter": {
        "status": 0
      },
      "limit": 100
    },
    "auth": "{{ $env.ZABBIX_API_TOKEN }}",
    "id": 1
  }
}
```

#### Step 2: Transform Data

```json
{
  "node": "Set",
  "values": {
    "problems": "={{ $json.result.map(p => ({
      host: p.hosts[0].name,
      severity: ['Not classified', 'Information', 'Warning', 'Average', 'High', 'Disaster'][p.severity],
      description: p.name,
      time: p.clock,
      status: p.status
    })) }}"
  }
}
```

#### Step 3: Return to Gateway

```json
{
  "node": "Respond to Webhook",
  "responseCode": 200,
  "responseData": "={{ $json }}"
}
```

### Workflow: Trigger Alert on Problem

**Name:** Zabbix Alert Handler

#### Step 1: Receive Zabbix Webhook

```json
{
  "node": "Webhook",
  "method": "POST",
  "path": "zabbix-alert"
}
```

#### Step 2: Check Severity

```json
{
  "node": "IF",
  "condition": "severity >= 4"  // High or Disaster
}
```

#### Step 3: Send Notification

```json
{
  "node": "Email",
  "to": "ops-team@internal.local",
  "subject": "🔴 {{$json.trigger.description}}",
  "body": "Host: {{$json.host.name}}\nSeverity: {{$json.severity}}\nMessage: {{$json.description}}"
}
```

---

## Part 4: FastAPI Gateway Integration

### Endpoint: Get Dashboard Data

Add to `src/backend/gateway/app/main.py`:

```python
from fastapi import FastAPI, HTTPException
import httpx
import os

app = FastAPI()

ZABBIX_API_URL = os.getenv("ZABBIX_API_URL", "https://zabbix.internal/api_jsonrpc.php")
ZABBIX_API_TOKEN = os.getenv("ZABBIX_API_TOKEN")

@app.get("/dashboard/zabbix/health")
async def get_zabbix_health():
    """Get current Zabbix health status"""
    
    payload = {
        "jsonrpc": "2.0",
        "method": "problem.get",
        "params": {
            "selectHosts": "extend",
            "filter": {"status": 0},
            "limit": 20
        },
        "auth": ZABBIX_API_TOKEN,
        "id": 1
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                ZABBIX_API_URL,
                json=payload,
                timeout=10.0
            )
            data = response.json()
            
            if "error" in data:
                raise HTTPException(status_code=400, detail=data["error"])
            
            problems = data.get("result", [])
            
            return {
                "status": "healthy" if len(problems) == 0 else "warning",
                "problem_count": len(problems),
                "problems": [
                    {
                        "host": p["hosts"][0]["name"],
                        "severity": ["Not classified", "Information", "Warning", "Average", "High", "Disaster"][int(p["severity"])],
                        "description": p["name"],
                        "timestamp": p["clock"]
                    }
                    for p in problems
                ]
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

@app.get("/dashboard/zabbix/hosts")
async def get_zabbix_hosts():
    """Get all monitored hosts"""
    
    payload = {
        "jsonrpc": "2.0",
        "method": "host.get",
        "params": {
            "output": ["hostid", "host", "name", "status"],
            "selectInterfaces": "extend",
            "limit": 100
        },
        "auth": ZABBIX_API_TOKEN,
        "id": 1
    }
    
    async with httpx.AsyncClient() as client:
        response = await client.post(ZABBIX_API_URL, json=payload, timeout=10.0)
        data = response.json()
        
        if "error" in data:
            raise HTTPException(status_code=400, detail=data["error"])
        
        hosts = data.get("result", [])
        return {
            "total": len(hosts),
            "hosts": [
                {
                    "name": h["name"],
                    "status": "enabled" if h["status"] == "0" else "disabled",
                    "ip": h["interfaces"][0]["ip"] if h.get("interfaces") else None
                }
                for h in hosts
            ]
        }

@app.get("/dashboard/zabbix/metrics/{host_name}")
async def get_host_metrics(host_name: str):
    """Get metrics for a specific host"""
    
    # First get host ID
    host_payload = {
        "jsonrpc": "2.0",
        "method": "host.get",
        "params": {
            "filter": {"host": host_name},
            "output": ["hostid"]
        },
        "auth": ZABBIX_API_TOKEN,
        "id": 1
    }
    
    # Then get items
    items_payload = {
        "jsonrpc": "2.0",
        "method": "item.get",
        "params": {
            "hostids": "{{ hostid }}",
            "output": ["itemid", "name", "lastvalue", "units"],
            "filter": {"type": ["0", "3"]},  # Zabbix agent, SNMP
            "limit": 50
        },
        "auth": ZABBIX_API_TOKEN,
        "id": 1
    }
    
    async with httpx.AsyncClient() as client:
        response = await client.post(ZABBIX_API_URL, json=host_payload, timeout=10.0)
        host_data = response.json()
        
        if not host_data.get("result"):
            raise HTTPException(status_code=404, detail=f"Host {host_name} not found")
        
        hostid = host_data["result"][0]["hostid"]
        items_payload["params"]["hostids"] = [hostid]
        
        response = await client.post(ZABBIX_API_URL, json=items_payload, timeout=10.0)
        items_data = response.json()
        
        return {
            "host": host_name,
            "metrics": [
                {
                    "name": item["name"],
                    "value": item["lastvalue"],
                    "unit": item["units"]
                }
                for item in items_data.get("result", [])
            ]
        }
```

### Update Requirements

Add to `src/backend/gateway/requirements.txt`:

```
httpx
```

---

## Part 5: Web UI Integration (Optional)

### Display Dashboard in Frontend

Create `src/frontend/dashboard.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>AI Assistant Dashboard</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background: #f5f5f5;
        }
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        .card {
            background: white;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .status-healthy { color: green; font-weight: bold; }
        .status-warning { color: orange; font-weight: bold; }
        .status-critical { color: red; font-weight: bold; }
        .metrics-list {
            list-style: none;
            padding: 0;
        }
        .metric-item {
            padding: 10px;
            border-bottom: 1px solid #eee;
        }
    </style>
</head>
<body>
    <h1>🔍 AI Assistant Dashboard</h1>
    
    <div class="dashboard">
        <div class="card" id="health-card">
            <h2>System Health</h2>
            <div id="health-status">Loading...</div>
        </div>
        
        <div class="card" id="hosts-card">
            <h2>Monitored Hosts</h2>
            <ul class="metrics-list" id="hosts-list">
                <li>Loading...</li>
            </ul>
        </div>
    </div>

    <script>
        async function loadDashboard() {
            try {
                // Load health
                const healthResp = await fetch('/dashboard/zabbix/health');
                const health = await healthResp.json();
                
                const statusClass = health.status === 'healthy' 
                    ? 'status-healthy' 
                    : 'status-warning';
                
                document.getElementById('health-status').innerHTML = `
                    <div class="${statusClass}">Status: ${health.status.toUpperCase()}</div>
                    <div>Problems: ${health.problem_count}</div>
                    ${health.problems.map(p => `
                        <div class="metric-item">
                            <strong>${p.host}</strong><br/>
                            ${p.description}
                        </div>
                    `).join('')}
                `;
                
                // Load hosts
                const hostsResp = await fetch('/dashboard/zabbix/hosts');
                const hosts = await hostsResp.json();
                
                document.getElementById('hosts-list').innerHTML = hosts.hosts
                    .map(h => `
                        <li class="metric-item">
                            ${h.name} (${h.status})<br/>
                            <small>${h.ip || 'N/A'}</small>
                        </li>
                    `).join('');
                    
            } catch (error) {
                console.error('Error loading dashboard:', error);
            }
        }
        
        // Load on page load and refresh every 30 seconds
        loadDashboard();
        setInterval(loadDashboard, 30000);
    </script>
</body>
</html>
```

---

## Part 6: Environment Variables

Add to `.env` or GitLab CI/CD variables:

```bash
ZABBIX_API_URL=https://zabbix.internal/api_jsonrpc.php
ZABBIX_API_TOKEN=<token-from-zabbix>
ZABBIX_API_USER=ai-assistant
ZABBIX_API_PASSWORD=<password>
```

---

## Part 7: Troubleshooting

| Issue | Solution |
|-------|----------|
| API authentication fails | Verify API token in Zabbix, check ZABBIX_API_TOKEN variable |
| Dashboard shows no data | Ensure hosts are in correct group, check user permissions |
| Slow response | Increase Zabbix API timeout, reduce query limit |
| WebSocket connection fails | Check Zabbix URL is accessible, verify SSL certificate |

---

## References

- Zabbix API: https://www.zabbix.com/documentation/current/en/manual/api
- Dashboard API: https://www.zabbix.com/documentation/current/en/manual/api/reference/dashboard
- Problem API: https://www.zabbix.com/documentation/current/en/manual/api/reference/problem
