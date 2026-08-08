# Harbor Registry Setup & Integration

This guide covers Harbor CE setup and integration with the ai-assistant project for private Docker image storage.

---

## Harbor Architecture Overview

```
Developers
    ↓
GitLab Runner
    ↓
Harbor Registry (Private)
    ├─ Projects
    ├─ Replication policies
    ├─ Vulnerability scanning
    └─ RBAC
    ↓
Deployment Servers
(Pull images from Harbor)
```

---

## Prerequisites

- Linux server (4+ CPU, 8+ GB RAM, 50+ GB storage recommended)
- Docker & Docker Compose installed
- Docker Hub account (for pulling base images) or offline installation
- SSL/TLS certificates for HTTPS (self-signed or CA-signed)
- Network: accessible from GitLab runners and deployment servers

---

## Harbor Installation

### 1. Download Harbor

```bash
# Download latest stable release
cd /opt
wget https://github.com/goharbor/harbor/releases/download/v2.8.0/harbor-offline-installer-v2.8.0.tgz
tar xzf harbor-offline-installer-v2.8.0.tgz
cd harbor
```

### 2. SSL Certificate Preparation

For HTTPS access (highly recommended):

```bash
# Option A: Use existing CA-signed certificate
cp /path/to/harbor.internal.crt ./certs/server.crt
cp /path/to/harbor.internal.key ./certs/server.key

# Option B: Generate self-signed certificate (for internal only)
mkdir -p certs
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout certs/server.key \
  -out certs/server.crt \
  -subj "/CN=harbor.internal"

# Verify certificate
openssl x509 -in certs/server.crt -noout -text
```

### 3. Configure harbor.yml

Edit `harbor.yml`:

```yaml
# Harbor configuration
hostname: harbor.internal

# HTTP and HTTPS
http:
  port: 80

https:
  port: 443
  certificate: /path/to/server.crt
  private_key: /path/to/server.key

# Internal TLS
internal_tls:
  enabled: true
  key_path: /path/to/internal/server.key
  cert_path: /path/to/internal/server.crt

# Harbor admin
harbor_admin_password: STRONG_ADMIN_PASSWORD

# Database (PostgreSQL)
database:
  password: STRONG_DB_PASSWORD
  max_idle_conns: 50
  max_open_conns: 100

# Data persistence
data_volume: /data/harbor

# Log
log:
  level: info
  local:
    rotate_count: 10
    rotate_size: 200M

# Garbage collection (cleanup unused blobs)
gc:
  auto_sweep: enabled
  sweep_dask: daily
```

### 4. Run Installation Script

```bash
# Prepare installation
sudo ./prepare

# Run installer
sudo ./install.sh

# Verify Harbor is running
docker-compose ps

# Access Harbor UI: https://harbor.internal/
# Default credentials: admin / <STRONG_ADMIN_PASSWORD>
```

---

## Harbor Post-Installation Setup

### 1. Create Project for ai-assistant

**Via Harbor UI:**

1. Log in as admin: https://harbor.internal/
2. Go to **Projects** → **+ New Project**
3. Create project:
   - Project name: `ai-assistant`
   - Access level: **Private**
   - Enable content trust: ✅
   - Enable vulnerability scanning: ✅
4. Click **OK**

**Via API:**

```bash
HARBOR_URL=https://harbor.internal
ADMIN_USER=admin
ADMIN_PASS=<password>
PROJECT_NAME=ai-assistant

curl -X POST ${HARBOR_URL}/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -u ${ADMIN_USER}:${ADMIN_PASS} \
  -d '{
    "project_name": "'${PROJECT_NAME}'",
    "metadata": {
      "public": "false"
    }
  }'
```

### 2. Create Harbor User for CI/CD

In Harbor UI: **Administration → Users → + New User**

```
Username: ci-bot
Password: STRONG_CI_PASSWORD
Realname: CI/CD Bot
Email: ci@internal.local
Comment: Used for GitLab CI/CD automation
```

Or via API:

```bash
curl -X POST ${HARBOR_URL}/api/v2.0/users \
  -H "Content-Type: application/json" \
  -u ${ADMIN_USER}:${ADMIN_PASS} \
  -d '{
    "username": "ci-bot",
    "password": "STRONG_CI_PASSWORD",
    "realname": "CI/CD Bot",
    "email": "ci@internal.local"
  }'
```

### 3. Assign Permissions to ci-bot

In Harbor UI: **Projects → ai-assistant → Members → + New**

Select `ci-bot` and assign role: **Developer** (or **Maintainer** if you want cleanup permissions)

Or via API:

```bash
# Get user ID
USER_ID=$(curl -s -u admin:password ${HARBOR_URL}/api/v2.0/users?username=ci-bot \
  | jq '.[0].user_id')

# Get project ID
PROJECT_ID=$(curl -s -u admin:password ${HARBOR_URL}/api/v2.0/projects?name=ai-assistant \
  | jq '.[0].project_id')

# Add user to project with Developer role
curl -X POST ${HARBOR_URL}/api/v2.0/projects/${PROJECT_ID}/members \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{
    "role_id": 2,
    "member_user": {
      "user_id": '${USER_ID}'
    }
  }'
```

### 4. Enable Vulnerability Scanning

In Harbor UI: **Administration → Configuration → Vulnerability Scanning**

- Scanner: Trivy (default)
- Auto scan on push: ✅

---

## Docker Login to Harbor

### On Developer Machine

```bash
# Add Harbor certificate to system trust (if self-signed)
sudo cp /path/to/harbor.internal.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Or: Skip cert verification (not recommended for production)
# echo '{"insecure-registries": ["harbor.internal:443"]}' | \
#   sudo tee /etc/docker/daemon.json

# Docker login
docker login harbor.internal:443
# Username: ci-bot
# Password: STRONG_CI_PASSWORD
```

### On GitLab Runner

```bash
# If using Docker runner, add to /etc/gitlab-runner/config.toml:
[[runners]]
  [runners.docker]
    registry = ["harbor.internal:443"]

# Or create ~/.docker/config.json:
cat > ~/.docker/config.json << EOF
{
  "auths": {
    "harbor.internal:443": {
      "auth": "$(echo -n 'ci-bot:STRONG_CI_PASSWORD' | base64)"
    }
  }
}
EOF
chmod 600 ~/.docker/config.json
```

### On Deployment Servers

```bash
# Login via systemd or at startup
mkdir -p ~/.docker
cat > ~/.docker/config.json << EOF
{
  "auths": {
    "harbor.internal:443": {
      "auth": "$(echo -n 'ci-bot:STRONG_CI_PASSWORD' | base64)"
    }
  }
}
EOF
chmod 600 ~/.docker/config.json

# Update docker-compose.yml to pull from Harbor:
# image: harbor.internal:443/ai-assistant/gateway:latest
```

---

## Image Naming Convention

All images should follow this pattern:

```
harbor.internal:443/ai-assistant/SERVICE_NAME:TAG
```

**Examples:**
- `harbor.internal:443/ai-assistant/gateway:latest`
- `harbor.internal:443/ai-assistant/gateway:v1.0.0`
- `harbor.internal:443/ai-assistant/gateway:abc1234def` (commit SHA)
- `harbor.internal:443/ai-assistant/n8n:latest`

---

## Replication Policies (Optional)

For disaster recovery, replicate to a secondary Harbor or registry:

**Via UI:** **Administration → Registries → + New Endpoint**

Then: **Projects → Replication Policies → + New Policy**

```yaml
Replication Policy:
  Name: backup-to-secondary
  Source: Current Harbor
  Destination: Secondary Harbor
  Filter: ai-assistant/* (all images in project)
  Trigger: On Push
  Override: enabled (allows overwriting older versions)
```

---

## Harbor Backup & Restore

### Backup

```bash
# Stop Harbor
cd /opt/harbor
docker-compose down

# Backup data volume
sudo tar -czf /backup/harbor-data-$(date +%Y%m%d).tar.gz /data/harbor

# Backup database
docker run -v /data/harbor/database:/src alpine tar czf /src/db-backup-$(date +%Y%m%d).tar.gz /src

# Restart Harbor
docker-compose up -d
```

### Restore

```bash
# Stop Harbor
docker-compose down

# Restore data
sudo rm -rf /data/harbor
sudo tar xzf /backup/harbor-data-YYYYMMDD.tar.gz -C /

# Restore database
docker run -v /data/harbor/database:/dst alpine tar xzf /dst/db-backup-YYYYMMDD.tar.gz -C /dst

# Restart Harbor
docker-compose up -d
```

---

## Monitoring & Maintenance

### Enable Garbage Collection

In `harbor.yml`:

```yaml
gc:
  auto_sweep: enabled
  sweep_dask: daily
```

This automatically removes unreferenced blobs (untagged images older than configured retention).

### Monitor Harbor Health

```bash
# Check harbor services
docker-compose ps

# View logs
docker-compose logs -f

# Disk usage
df -h /data/harbor

# Database status
docker exec harbor-db psql -U postgres -c "SELECT database_size(current_database());"
```

### Update Harbor

```bash
cd /opt/harbor

# Download new version
wget https://github.com/goharbor/harbor/releases/download/v2.9.0/harbor-offline-installer-v2.9.0.tgz
tar xzf harbor-offline-installer-v2.9.0.tgz -C ../harbor-v2.9.0 --strip-components=1

# Run migration
cd ../harbor-v2.9.0
sudo ./prepare
sudo docker-compose up -d

# Verify
curl -k https://harbor.internal/api/v2.0/systeminfo -u admin:password
```

---

## Integration with ai-assistant

### Update docker-compose.yml

```yaml
version: '3.8'

services:
  gateway:
    image: harbor.internal:443/ai-assistant/gateway:${GATEWAY_TAG:-latest}
    container_name: ai_gateway
    environment:
      - N8N_WEBHOOK_URL=http://n8n:5678/webhook/ai-gateway
      - LITELLM_URL=http://litellm:4000/v1/chat/completions
    depends_on:
      - n8n
    ports:
      - "8080:8080"

  # Note: Image pull credentials must be configured via docker login
  # Or in GitLab CI variables: HARBOR_USER, HARBOR_PASSWORD
```

### GitLab CI Configuration

See `.gitlab/GITLAB_CI_SETUP.md` for full CI/CD integration.

Key CI/CD variables:

```
HARBOR_REGISTRY=harbor.internal:443
HARBOR_PROJECT=ai-assistant
HARBOR_USER=ci-bot
HARBOR_PASSWORD=<strong-password>
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Cannot login to Harbor | Verify credentials, check Harbor is running (`docker-compose logs`), verify network connectivity |
| Image push fails | Check disk space, verify user permissions, check Docker daemon logs |
| Self-signed cert warning | Add cert to system trust store or use `docker login --insecure` |
| Vulnerability scanning not working | Ensure Trivy scanner is enabled in Harbor config, check internet connectivity for vulnerability DB |
| Very slow image pulls | Check network bandwidth, enable image caching, verify Harbor disk I/O |

---

## Security Hardening

1. **Change default admin password immediately** after installation
2. **Enable RBAC** (Projects → Members) instead of public access
3. **Use TLS/HTTPS** (self-signed OK for internal use)
4. **Restrict network access** via firewall; only allow runners and deployment servers
5. **Rotate CI credentials** regularly (ci-bot password)
6. **Enable audit logging** (Administration → Configuration → Audit Log)
7. **Use Harbor API tokens** (Account → Personal Token) instead of passwords when possible

---

## References

- Harbor Official Docs: https://goharbor.io/docs/
- Harbor API Reference: https://github.com/goharbor/harbor/blob/main/api/v2.0/swagger.yaml
- Vulnerability Scanning: https://goharbor.io/docs/working-with-projects/working-with-images/scan-images/
- Replication: https://goharbor.io/docs/working-with-registries/
