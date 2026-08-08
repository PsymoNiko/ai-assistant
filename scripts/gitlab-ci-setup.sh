#!/bin/bash
# scripts/gitlab-ci-setup.sh
# Setup GitLab CI/CD pipeline and Harbor integration
# Usage: bash scripts/gitlab-ci-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==========================================="
echo "GitLab CI/CD Setup for ai-assistant"
echo "==========================================="

# 1. Create .gitlab-ci.yml
echo ""
echo "[1/5] Creating .gitlab-ci.yml..."
if [ ! -f "$PROJECT_ROOT/.gitlab-ci.yml" ]; then
  cat > "$PROJECT_ROOT/.gitlab-ci.yml" << 'EOF'
# See .gitlab/GITLAB_CI_SETUP.md for full documentation

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

image: docker:latest
services:
  - docker:dind

before_script:
  - docker login -u $HARBOR_USER -p $HARBOR_PASSWORD $HARBOR_REGISTRY

# Build stage
build:gateway:
  stage: build
  script:
    - cd src/backend/gateway
    - docker build -t gateway:$CI_COMMIT_SHA .
    - docker tag gateway:$CI_COMMIT_SHA gateway:latest
  only:
    - main
    - develop

# Lint stage
lint:python:
  stage: lint
  image: python:3.11
  script:
    - pip install flake8
    - flake8 src/backend/ --max-line-length=120 || true
  only:
    - merge_requests

# Test stage (placeholder)
test:unit:
  stage: test
  image: python:3.11
  script:
    - pip install -r src/backend/gateway/requirements.txt
    - echo "Unit tests would run here"
  only:
    - merge_requests
    - main

# Publish stage
publish:gateway:
  stage: publish
  script:
    - docker build -t ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/gateway:${CI_COMMIT_SHA} src/backend/gateway/
    - docker tag ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/gateway:${CI_COMMIT_SHA} ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/gateway:latest
    - docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/gateway:${CI_COMMIT_SHA}
    - docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/gateway:latest
  only:
    - main
    - develop

# Deploy stages (manual)
deploy:dev:
  stage: deploy-dev
  script:
    - echo "Deploy to dev environment"
  environment:
    name: development
  only:
    - develop
  when: manual

deploy:prod:
  stage: deploy-prod
  script:
    - echo "Deploy to production"
  environment:
    name: production
  only:
    - main
  when: manual
EOF
  echo "✅ Created .gitlab-ci.yml"
else
  echo "⚠️  .gitlab-ci.yml already exists, skipping"
fi

# 2. Create .gitlab/ci/scripts directory
echo ""
echo "[2/5] Creating .gitlab/ci/scripts directory..."
mkdir -p "$PROJECT_ROOT/.gitlab/ci/scripts"
echo "✅ Created .gitlab/ci/scripts/"

# 3. Create sample push script
echo ""
echo "[3/5] Creating Harbor push script..."
cat > "$PROJECT_ROOT/.gitlab/ci/scripts/push-to-harbor.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

SERVICE=${1:-gateway}
HARBOR_REGISTRY=${HARBOR_REGISTRY:-harbor.internal:443}
HARBOR_PROJECT=${HARBOR_PROJECT:-ai-assistant}
TAG=${CI_COMMIT_SHA:-latest}

echo "Pushing $SERVICE to Harbor..."
docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:${TAG}
docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${SERVICE}:latest
echo "✅ Image pushed successfully"
EOF
chmod +x "$PROJECT_ROOT/.gitlab/ci/scripts/push-to-harbor.sh"
echo "✅ Created push-to-harbor.sh"

# 4. Create merge request template
echo ""
echo "[4/5] Creating merge request template..."
mkdir -p "$PROJECT_ROOT/.gitlab/merge_request_templates"
cat > "$PROJECT_ROOT/.gitlab/merge_request_templates/default.md" << 'EOF'
## Description
<!-- Describe your changes -->

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Infrastructure

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing done

## Checklist
- [ ] Code follows conventions
- [ ] No secrets exposed
- [ ] Documentation updated
- [ ] Tests added/updated
EOF
echo "✅ Created merge request template"

# 5. Create docker-compose example
echo ""
echo "[5/5] Creating docker-compose example for Harbor..."
if [ ! -f "$PROJECT_ROOT/docker-compose.harbor.yml" ]; then
  cat > "$PROJECT_ROOT/docker-compose.harbor.yml" << 'EOF'
# Example docker-compose.yml using Harbor registry
version: '3.8'

services:
  gateway:
    image: harbor.internal:443/ai-assistant/gateway:latest
    container_name: ai_gateway
    ports:
      - "8080:8080"
    environment:
      - N8N_WEBHOOK_URL=http://n8n:5678/webhook/ai-gateway
      - LITELLM_URL=http://litellm:4000/v1/chat/completions

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOF
  echo "✅ Created docker-compose.harbor.yml"
fi

# Summary
echo ""
echo "==========================================="
echo "✅ GitLab CI/CD Setup Complete!"
echo "==========================================="
echo ""
echo "Next steps:"
echo "1. Review and customize .gitlab-ci.yml"
echo "2. Add GitLab CI/CD variables in project settings:"
echo "   - HARBOR_REGISTRY: harbor.internal:443"
echo "   - HARBOR_PROJECT: ai-assistant"
echo "   - HARBOR_USER: ci-bot"
echo "   - HARBOR_PASSWORD: <masked>"
echo "3. Push changes: git add . && git commit -m 'CI/CD: Add GitLab CI/CD pipeline'"
echo "4. Create merge request to trigger pipeline"
echo ""
echo "Documentation:"
echo "- .gitlab/GITLAB_CI_SETUP.md      (Complete CI/CD setup)"
echo "- docs/harbor/HARBOR_SETUP.md     (Harbor registry setup)"
echo "- docs/gitlab-ce/GITLAB_CE_SETUP.md (GitLab CE setup)"
echo ""
