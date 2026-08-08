# Harbor Registry Configuration

Quick reference for Harbor registry endpoints and image management.

---

## Harbor Endpoints

All endpoints use HTTPS (self-signed certificate is OK for internal):

- **Web UI**: https://harbor.internal/
- **Docker Registry API**: https://harbor.internal:443/v2/
- **Harbor API (v2.0)**: https://harbor.internal/api/v2.0/

---

## Example .gitlab-ci.yml Build & Push

```yaml
stages:
  - build
  - push

variables:
  REGISTRY: harbor.internal:443
  PROJECT: ai-assistant

build:gateway:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    - cd src/backend/gateway
    - docker build -t gateway:${CI_COMMIT_SHA} .
  artifacts:
    paths:
      - src/backend/gateway/

push:gateway:
  stage: push
  image: docker:latest
  services:
    - docker:dind
  before_script:
    - docker login -u $HARBOR_USER -p $HARBOR_PASSWORD $REGISTRY
  script:
    - docker load -i src/backend/gateway/image.tar
    - docker tag gateway:${CI_COMMIT_SHA} ${REGISTRY}/${PROJECT}/gateway:${CI_COMMIT_SHA}
    - docker tag gateway:${CI_COMMIT_SHA} ${REGISTRY}/${PROJECT}/gateway:latest
    - docker push ${REGISTRY}/${PROJECT}/gateway:${CI_COMMIT_SHA}
    - docker push ${REGISTRY}/${PROJECT}/gateway:latest
```

---

## Example docker-compose.yml with Harbor

```yaml
version: '3.8'

services:
  gateway:
    image: harbor.internal:443/ai-assistant/gateway:latest
    container_name: ai_gateway
    restart: always
    ports:
      - "8080:8080"
    environment:
      - N8N_WEBHOOK_URL=http://n8n:5678/webhook/ai-gateway
      - LITELLM_URL=http://litellm:4000/v1/chat/completions
    depends_on:
      - n8n

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=false
    volumes:
      - n8n_data:/home/node/.n8n

  # ... other services ...

volumes:
  n8n_data:
```

---

## Registry Authentication

### For Docker CLI

```bash
# Login
docker login harbor.internal:443
# Username: ci-bot
# Password: <STRONG_PASSWORD>

# Logout
docker logout harbor.internal:443
```

### For docker-compose & deployment servers

Create `~/.docker/config.json`:

```json
{
  "auths": {
    "harbor.internal:443": {
      "auth": "Y2ktYm90OlNUUk9OR19QQVNTV09SRA=="
    }
  }
}
```

(Encode credentials: `echo -n "ci-bot:PASSWORD" | base64`)

---

## Push Example

```bash
# Tag image
docker tag myapp:latest harbor.internal:443/ai-assistant/myapp:latest

# Push
docker push harbor.internal:443/ai-assistant/myapp:latest

# Verify (check Harbor UI or API)
curl -k -u ci-bot:password https://harbor.internal/api/v2.0/projects/ai-assistant/repositories
```

---

## Pull Example

```bash
# Pull image
docker pull harbor.internal:443/ai-assistant/gateway:latest

# Run container
docker run -it harbor.internal:443/ai-assistant/gateway:latest
```

---

## Harbor Project Structure

```
ai-assistant/
├── gateway            # FastAPI gateway container image
├── n8n               # n8n workflow engine (optional if using Docker Hub)
├── litellm           # LiteLLM adapter (optional if using Docker Hub)
└── [other services]
```

---

## Vulnerability Scanning

Harbor automatically scans images for vulnerabilities. View results:

1. Navigate to **Projects → ai-assistant → Repositories → gateway**
2. Click on image tag
3. See vulnerability report from Trivy scanner

Scan results are also available via API:

```bash
curl -k -u admin:password \
  https://harbor.internal/api/v2.0/projects/ai-assistant/repositories/gateway/artifacts/latest/scan
```

---

## Image Cleanup & Garbage Collection

Harbor automatically garbage collects unreferenced blobs. To manually trigger:

**Harbor UI → Administration → Garbage Collection → GC Now**

Or via scheduler (daily at 2 AM):

**Harbor UI → Administration → Garbage Collection → Daily schedule**

---

## Disaster Recovery

If Harbor becomes unavailable:

1. **Temporary workaround:** Use Docker Hub or another public registry for CI/CD
2. **Restore from backup:** See `docs/harbor/HARBOR_SETUP.md` → Backup & Restore section
3. **Access existing images:** Docker layers are cached on deployment servers; services will continue running

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| `docker login` fails | Verify user exists in Harbor; check network connectivity |
| Image push timeout | Check disk space: `docker exec harbor-db df -h`; increase timeout in CI/CD |
| Certificate warning | Add cert to system trust or `docker login --insecure` |
| Vulnerability scan timeout | Check Trivy DB is updated; restart Harbor |

---

**Note:** For full Harbor setup, see `docs/harbor/HARBOR_SETUP.md`
