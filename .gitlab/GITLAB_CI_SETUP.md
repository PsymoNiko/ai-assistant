# GitLab CI/CD Setup for ai-assistant

This document guides setup of GitLab CI/CD pipelines for the ai-assistant project on self-hosted GitLab CE, with integration to Harbor private registry.

---

## Prerequisites

- GitLab CE instance running (version 15.0+)
- Docker-in-Docker runner or shell runner with Docker installed
- Access to Harbor registry (see `docs/harbor/HARBOR_SETUP.md`)
- SSH access to deployment servers
- GitLab runner registered and running

---

## GitLab Runner Setup

### 1. Register a Docker Runner

```bash
# On your runner machine (Linux server with Docker installed)
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# Register runner for ai-assistant project
sudo gitlab-runner register \
  --url https://your-gitlab.internal/ \
  --registration-token PROJECT_RUNNER_TOKEN \
  --executor docker \
  --docker-image docker:latest \
  --docker-privileged \
  --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
  --tag-list docker,linux \
  --run-untagged=false \
  --name ai-assistant-docker-runner

# Restart runner
sudo systemctl restart gitlab-runner
```

**Alternative: Shell Runner** (if Docker-in-Docker is not available)

```bash
sudo gitlab-runner register \
  --url https://your-gitlab.internal/ \
  --registration-token PROJECT_RUNNER_TOKEN \
  --executor shell \
  --name ai-assistant-shell-runner
```

### 2. Configure Harbor Registry Access

Create `/etc/gitlab-runner/config.toml` entry for Harbor registry:

```toml
[[runners]]
  name = "ai-assistant-docker-runner"
  url = "https://your-gitlab.internal/"
  token = "RUNNER_TOKEN"
  executor = "docker"
  
  [runners.docker]
    image = "docker:latest"
    privileged = true
    volumes = ["/var/run/docker.sock:/var/run/docker.sock"]
    pull_policy = "if-not-present"
    registry = ["harbor.internal:443"]
```

Add Harbor credentials to runner machine:

```bash
docker login harbor.internal:443 \
  -u harbor-user \
  -p harbor-password
```

---

## GitLab CI/CD Pipeline Structure

### Pipeline Stages

```
1. build        → Compile, package, test
2. lint         → Code quality, security scanning
3. test         → Unit, integration, e2e tests
4. publish      → Push images to Harbor
5. deploy-dev   → Deploy to development environment
6. deploy-prod  → Deploy to production (manual approval)
7. smoke-test   → Verify deployment health
```

### File Structure

```
.gitlab/
├── GITLAB_CI_SETUP.md      # This file
├── .gitlab-ci.yml          # Main CI/CD pipeline (root)
└── ci/
    ├── scripts/            # Helper scripts
    │   ├── build-image.sh
    │   ├── push-to-harbor.sh
    │   ├── deploy.sh
    │   └── smoke-test.sh
    └── templates/          # Job templates (optional)
```

---

## .gitlab-ci.yml Configuration

Main pipeline file at repository root:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - lint
  - test
  - publish
  - deploy-dev
  - deploy-prod
  - smoke-test

variables:
  HARBOR_REGISTRY: "harbor.internal:443"
  HARBOR_PROJECT: "ai-assistant"
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_VERIFY: 1
  DOCKER_TLS_CERTDIR: "/certs"

# Docker build configuration
image: docker:latest

services:
  - docker:dind

before_script:
  - docker login -u $HARBOR_USER -p $HARBOR_PASSWORD $HARBOR_REGISTRY

# ============== BUILD STAGE ==============
build:gateway:
  stage: build
  script:
    - cd src/backend/gateway
    - docker build -t gateway:$CI_COMMIT_SHA .
    - docker tag gateway:$CI_COMMIT_SHA gateway:latest
  artifacts:
    paths:
      - src/backend/gateway/
    expire_in: 1 day
  only:
    - main
    - develop
    - /^release\/.*$/

# ============== LINT STAGE ==============
lint:python:
  stage: lint
  image: python:3.11
  script:
    - pip install flake8 pylint
    - flake8 src/backend/ --max-line-length=120
    - pylint src/backend/gateway/app/main.py
  only:
    - merge_requests
    - main
    - develop

lint:workflows:
  stage: lint
  image: node:18
  script:
    - npm install -g ajv-cli
    - ajv validate -s docs/n8n-workflow-schema.json -d 'workflows/*.json'
  artifacts:
    reports:
      sast: gl-sast-report.json
  only:
    - merge_requests
    - main

# ============== TEST STAGE ==============
test:unit:
  stage: test
  image: python:3.11
  script:
    - pip install -r src/backend/gateway/requirements.txt
    - pip install pytest pytest-cov
    - pytest tests/unit/ -v --cov=src/backend/gateway --cov-report=xml
  coverage: '/(?i)total.*? (100(?:\.0+)?\%|[1-9]?\d(?:\.\d+)?\%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
  only:
    - merge_requests
    - main

test:integration:
  stage: test
  services:
    - postgres:15
    - redis:7
  script:
    - pip install -r src/backend/gateway/requirements.txt pytest
    - pytest tests/integration/ -v
  only:
    - merge_requests
    - main

# ============== PUBLISH STAGE ==============
publish:gateway:
  stage: publish
  script:
    - bash .gitlab/ci/scripts/push-to-harbor.sh gateway
  environment:
    name: harbor-registry
  only:
    - main
    - develop
    - /^release\/.*$/
  when: on_success

# ============== DEPLOY STAGE (DEV) ==============
deploy:dev:
  stage: deploy-dev
  environment:
    name: development
    url: http://gateway-dev.internal:8080
    deployment_tier: development
  script:
    - bash .gitlab/ci/scripts/deploy.sh dev
  only:
    - develop
  when: on_success

# ============== DEPLOY STAGE (PROD) ==============
deploy:prod:
  stage: deploy-prod
  environment:
    name: production
    url: http://gateway-prod.internal:8080
    deployment_tier: production
  script:
    - bash .gitlab/ci/scripts/deploy.sh prod
  only:
    - main
  when: manual
  allow_failure: false

# ============== SMOKE TEST ==============
smoke-test:dev:
  stage: smoke-test
  environment:
    name: development
  script:
    - bash .gitlab/ci/scripts/smoke-test.sh dev
  dependencies:
    - deploy:dev
  only:
    - develop
  when: on_success

smoke-test:prod:
  stage: smoke-test
  environment:
    name: production
  script:
    - bash .gitlab/ci/scripts/smoke-test.sh prod
  dependencies:
    - deploy:prod
  only:
    - main
  when: on_success
```

---

## Helper Scripts

### Build Image (.gitlab/ci/scripts/build-image.sh)

```bash
#!/bin/bash
set -euo pipefail

SERVICE=$1
HARBOR_REGISTRY=${HARBOR_REGISTRY:-harbor.internal:443}
HARBOR_PROJECT=${HARBOR_PROJECT:-ai-assistant}
TAG=${CI_COMMIT_SHA}

echo "Building $SERVICE..."
cd src/backend/$SERVICE

docker build -t ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:${TAG} .
docker tag ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:${TAG} \
           ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:latest

echo "Image built: ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:${TAG}"
```

### Push to Harbor (.gitlab/ci/scripts/push-to-harbor.sh)

```bash
#!/bin/bash
set -euo pipefail

SERVICE=$1
HARBOR_REGISTRY=${HARBOR_REGISTRY:-harbor.internal:443}
HARBOR_PROJECT=${HARBOR_PROJECT:-ai-assistant}
TAG=${CI_COMMIT_SHA}

echo "Pushing $SERVICE to Harbor..."
docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:${TAG}
docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:latest

echo "Image pushed: ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:${TAG}"
```

### Deploy Script (.gitlab/ci/scripts/deploy.sh)

```bash
#!/bin/bash
set -euo pipefail

ENVIRONMENT=$1
HARBOR_REGISTRY=${HARBOR_REGISTRY:-harbor.internal:443}
HARBOR_PROJECT=${HARBOR_PROJECT:-ai-assistant}
TAG=${CI_COMMIT_SHA}

echo "Deploying to $ENVIRONMENT..."

if [ "$ENVIRONMENT" = "dev" ]; then
  DEPLOY_HOST="dev-server.internal"
  DOCKER_COMPOSE_URL="https://gitlab.internal/api/v4/projects/${CI_PROJECT_ID}/repository/files/docker-compose.yml/raw?ref=${CI_COMMIT_SHA}"
else
  DEPLOY_HOST="prod-server.internal"
  DOCKER_COMPOSE_URL="https://gitlab.internal/api/v4/projects/${CI_PROJECT_ID}/repository/files/docker-compose.yml/raw?ref=${CI_COMMIT_SHA}"
fi

# SSH to deployment host and pull latest images
ssh -i /root/.ssh/deploy_key_${ENVIRONMENT} deploy@${DEPLOY_HOST} << EOF
  set -euo pipefail
  cd /opt/ai-assistant
  
  # Login to Harbor
  docker login -u \$HARBOR_USER -p \$HARBOR_PASSWORD ${HARBOR_REGISTRY}
  
  # Pull latest images
  docker-compose pull
  
  # Restart services
  docker-compose up -d
  
  echo "Deployed to ${ENVIRONMENT}"
EOF
```

### Smoke Test (.gitlab/ci/scripts/smoke-test.sh)

```bash
#!/bin/bash
set -euo pipefail

ENVIRONMENT=$1

if [ "$ENVIRONMENT" = "dev" ]; then
  GATEWAY_URL="http://gateway-dev.internal:8080"
else
  GATEWAY_URL="http://gateway-prod.internal:8080"
fi

echo "Running smoke tests against $GATEWAY_URL..."

# Test gateway health
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" ${GATEWAY_URL}/health || echo "000")
if [ "$HEALTH" != "200" ]; then
  echo "❌ Gateway health check failed (HTTP $HEALTH)"
  exit 1
fi

# Test AI gateway endpoint
RESPONSE=$(curl -s -X POST ${GATEWAY_URL}/ai-gateway \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}')

if echo "$RESPONSE" | grep -q "error"; then
  echo "❌ AI Gateway endpoint failed"
  echo "$RESPONSE"
  exit 1
fi

# Test n8n connectivity
N8N_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://n8n.internal:5678/health || echo "000")
if [ "$N8N_STATUS" != "200" ]; then
  echo "⚠️  n8n health check failed (HTTP $N8N_STATUS)"
fi

echo "✅ Smoke tests passed!"
```

---

## GitLab CI/CD Variables Setup

In GitLab project: **Settings → CI/CD → Variables**

Add the following protected/masked variables:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `HARBOR_REGISTRY` | `harbor.internal:443` | ✅ | ❌ |
| `HARBOR_PROJECT` | `ai-assistant` | ✅ | ❌ |
| `HARBOR_USER` | Harbor username | ✅ | ✅ |
| `HARBOR_PASSWORD` | Harbor password | ✅ | ✅ |
| `DEPLOY_HOST_DEV` | `dev-server.internal` | ✅ | ❌ |
| `DEPLOY_HOST_PROD` | `prod-server.internal` | ✅ | ❌ |
| `SSH_PRIVATE_KEY_DEV` | SSH key for dev deployment | ✅ | ✅ |
| `SSH_PRIVATE_KEY_PROD` | SSH key for prod deployment | ✅ | ✅ |
| `ZABBIX_API_URL` | Zabbix API endpoint | ✅ | ❌ |
| `ZABBIX_API_TOKEN` | Zabbix API token | ✅ | ✅ |

---

## Protected Branches & Approval Rules

### Branch Protection

**Settings → Repository → Branch Protection**

```
main:
  - Require approval count: 2
  - Dismiss stale approvals: enabled
  - Restrict who can push: Maintainers
  - Require all conversations resolved: enabled
  - Require CI to pass: enabled

develop:
  - Require approval count: 1
  - Require CI to pass: enabled
```

### Approval Rules

**Settings → General → Approval rules**

```
Deploy to Production:
  - Approvers: 2 (from security team + tech lead)
  - Source branches: main
  - Merge requests: Manual approval for deploy:prod job
```

---

## Merge Request Workflow

### Template (.gitlab/merge_request_templates/default.md)

```markdown
## Description
<!-- Describe your changes -->

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Configuration/documentation
- [ ] Infrastructure change

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests passed
- [ ] Manual testing performed on: _____

## Security Checklist
- [ ] No secrets/credentials exposed
- [ ] No hardcoded values
- [ ] Harbor credentials/SSH keys not in code
- [ ] Data sensitivity reviewed

## Deployment Notes
- [ ] Database migration required?
- [ ] New dependencies?
- [ ] Configuration changes?
- [ ] Rollback plan documented?

## Checklist
- [ ] Code follows project conventions
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Linting passes
- [ ] Tests pass
- [ ] Documentation updated
```

---

## Monitoring Pipeline Health

### GitLab Pipeline Dashboard

Access at: `https://your-gitlab.internal/your-group/ai-assistant/-/pipelines`

### Key Metrics to Monitor

- Pipeline success rate (aim for >95%)
- Average pipeline duration
- Failed job breakdown by stage
- Deployment frequency to dev/prod

### Troubleshooting Common Issues

| Issue | Solution |
|-------|----------|
| Docker login fails | Check `HARBOR_USER`/`HARBOR_PASSWORD` in CI variables; refresh token if needed |
| Runner not picking up jobs | Verify runner has correct tags; check runner status with `gitlab-runner verify` |
| SSH deployment fails | Verify SSH key is in CI variables; check known_hosts on deployment host |
| Harbor image push timeout | Increase timeout in `.gitlab-ci.yml`; check Harbor disk space |
| Smoke test fails after deploy | Check service logs: `docker-compose logs gateway` on deployment host |

---

## Next Steps

1. Create `.gitlab-ci.yml` at repository root (see example above)
2. Create `.gitlab/ci/scripts/` directory with helper scripts
3. Create `.gitlab/merge_request_templates/default.md`
4. Register GitLab runners (Docker or Shell)
5. Add CI/CD variables to project settings
6. Test pipeline with a merge request
7. Configure branch protection and approval rules
8. Set up Slack/email notifications (optional)

---

**Reference:**
- GitLab CI/CD Docs: https://docs.gitlab.com/ee/ci/
- GitLab Runner: https://docs.gitlab.com/runner/
- Docker Executor: https://docs.gitlab.com/runner/executors/docker.html
