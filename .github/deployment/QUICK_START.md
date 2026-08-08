# Private Network Configuration Guide

This document provides step-by-step instructions for configuring the ai-assistant on a private network with GitLab CE and Harbor.

---

## Quick Start Checklist

- [ ] Read `docs/gitlab-ce/GITLAB_CE_SETUP.md` - GitLab CE installation
- [ ] Read `docs/harbor/HARBOR_SETUP.md` - Harbor registry setup
- [ ] Read `.gitlab/GITLAB_CI_SETUP.md` - CI/CD pipeline configuration
- [ ] Read `.github/deployment/PRIVATE_NETWORK_DEPLOYMENT.md` - Complete deployment guide
- [ ] Run `bash scripts/gitlab-ci-setup.sh` - Setup GitLab CI/CD files

---

## 30-Minute Quick Setup

### Step 1: Prepare Network (5 min)

```bash
# Add DNS entries to /etc/hosts on all machines
# (or configure in your DNS server)
192.168.1.10  gitlab.internal
192.168.1.11  harbor.internal
192.168.1.30  runner.internal
192.168.1.100 dev-server.internal
192.168.1.101 prod-server.internal
```

### Step 2: Deploy GitLab CE (10 min)

On GitLab server (192.168.1.10):

```bash
cd /opt
mkdir -p gitlab/ssl
cd gitlab

# Generate self-signed certificate (if needed)
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout ssl/gitlab.internal.key \
  -out ssl/gitlab.internal.crt \
  -subj "/CN=gitlab.internal"

# Create docker-compose.yml (see docs/gitlab-ce/GITLAB_CE_SETUP.md)
# Then start:
docker-compose up -d

# Wait 5-10 minutes for initialization
docker-compose logs -f gitlab | grep "Waiting"
```

Access: https://gitlab.internal/ (accept SSL warning)

### Step 3: Deploy Harbor (10 min)

On Harbor server (192.168.1.11):

```bash
cd /opt
wget https://github.com/goharbor/harbor/releases/download/v2.8.0/harbor-offline-installer-v2.8.0.tgz
tar xzf harbor-offline-installer-v2.8.0.tgz
cd harbor

# Generate certificate
mkdir -p certs
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout certs/server.key \
  -out certs/server.crt \
  -subj "/CN=harbor.internal"

# Edit harbor.yml (update hostname, password)
# Then install:
sudo ./prepare
sudo ./install.sh
```

Access: https://harbor.internal/ (username: admin / password from harbor.yml)

### Step 4: Setup CI/CD (5 min)

In local repo clone:

```bash
bash scripts/gitlab-ci-setup.sh

# Commit and push to GitLab
git add .gitlab/ .gitlab-ci.yml docker-compose.harbor.yml
git commit -m "CI/CD: Add GitLab CI/CD pipeline and Harbor integration"
git push -u origin main
```

---

## File Structure Created

```
.github/
├── copilot-instructions.md          # AI assistant guidance
├── deployment/
│   └── PRIVATE_NETWORK_DEPLOYMENT.md
└── registry/
    └── HARBOR_REGISTRY.md

.gitlab/
├── GITLAB_CI_SETUP.md               # Complete CI/CD guide
└── ci/
    └── scripts/
        └── push-to-harbor.sh

docs/
├── gitlab-ce/
│   └── GITLAB_CE_SETUP.md           # GitLab CE installation
└── harbor/
    └── HARBOR_SETUP.md               # Harbor registry setup

scripts/
└── gitlab-ci-setup.sh               # Setup automation

.gitlab-ci.yml                        # GitLab CI/CD pipeline
docker-compose.harbor.yml            # Example with Harbor images
```

---

## Configuration Files Needed

### 1. .gitlab/ci/scripts/deploy.sh

Edit to match your deployment servers:

```bash
#!/bin/bash
ENVIRONMENT=$1
DEPLOY_HOST="your-$ENVIRONMENT-server.internal"
ssh -i ~/.ssh/deploy_key deploy@${DEPLOY_HOST} << EOF
  cd /opt/ai-assistant
  docker-compose pull
  docker-compose up -d
EOF
```

### 2. GitLab CI/CD Variables

In GitLab: **Projects → ai-assistant → Settings → CI/CD → Variables**

Add:
```
HARBOR_REGISTRY=harbor.internal:443
HARBOR_PROJECT=ai-assistant
HARBOR_USER=ci-bot
HARBOR_PASSWORD=<from Harbor setup>
SSH_PRIVATE_KEY_DEV=<SSH key for dev server>
SSH_PRIVATE_KEY_PROD=<SSH key for prod server>
```

### 3. .env Files on Deployment Servers

On dev and prod servers:

```bash
# /opt/ai-assistant/.env
N8N_WEBHOOK_URL=http://n8n:5678/webhook/ai-gateway
LITELLM_URL=http://litellm:4000/v1/chat/completions
```

---

## Verification Steps

### Verify GitLab CE

```bash
curl -k https://gitlab.internal/
# Should return HTML with GitLab login page
```

### Verify Harbor

```bash
docker login harbor.internal:443 -u admin -p <password>
curl -k -u admin:<password> https://harbor.internal/api/v2.0/projects
# Should list projects
```

### Verify GitLab Runner

In GitLab: **Admin Area → Runners**
- Should show registered runner(s) with green indicator

### Verify CI/CD Pipeline

1. Create test merge request
2. GitLab CI/CD → **Pipelines**
3. Should see pipeline running through stages
4. Check image in Harbor: **Projects → ai-assistant → Repositories**

---

## Troubleshooting Guide

### GitLab CE won't start

```bash
docker-compose logs gitlab
# Check disk space, RAM, Docker daemon status
docker system df
```

### Harbor login fails

```bash
# Check Harbor is running
docker-compose ps

# Check user exists
curl -k -u admin:password https://harbor.internal/api/v2.0/users

# Verify certificate trusted (Linux)
sudo update-ca-certificates
```

### CI/CD pipeline fails at Harbor push

```bash
# Check credentials in GitLab CI variables (masked by default)
# Verify user permissions in Harbor: Projects → ai-assistant → Members

# Test manually on runner:
docker login harbor.internal:443 -u ci-bot -p <password>
docker push harbor.internal:443/ai-assistant/test:latest
```

### SSH deployment fails

```bash
# Check SSH key is set in GitLab CI variables
# Verify key on deployment server:
cat ~/.ssh/authorized_keys

# Test SSH:
ssh -i ~/.ssh/deploy_key deploy@dev-server.internal "docker-compose ps"
```

---

## Next Steps

1. **Read the full setup guides:**
   - `docs/gitlab-ce/GITLAB_CE_SETUP.md` - 10,000+ characters
   - `docs/harbor/HARBOR_SETUP.md` - 10,000+ characters
   - `.gitlab/GITLAB_CI_SETUP.md` - 13,000+ characters

2. **Customize for your environment:**
   - Update IP addresses in network diagrams
   - Update DNS hostnames
   - Configure SSL certificates (CA-signed recommended for production)
   - Adjust resource limits (CPU, RAM) based on your infrastructure

3. **Setup deployment:**
   - Follow `.github/deployment/PRIVATE_NETWORK_DEPLOYMENT.md`
   - Provision servers (dev, prod)
   - Configure SSH keys
   - Test end-to-end deployment

4. **Monitor production:**
   - Setup alerts in Zabbix (optional)
   - Configure backup automation
   - Create runbooks for common issues

---

## Common Tasks

### Deploy a new version to production

```bash
# 1. Merge to main branch
git merge develop

# 2. Pipeline runs automatically
# - Builds image
# - Pushes to Harbor
# - Awaits manual approval for prod deployment

# 3. Click "Deploy" in GitLab CI/CD UI

# 4. Smoke tests run automatically
```

### Rollback to previous version

```bash
# On production server
cd /opt/ai-assistant
git log --oneline  # Find previous commit
git checkout <previous-commit>
docker-compose pull
docker-compose up -d
```

### Rotate Harbor credentials

```bash
# In Harbor UI: Administration → Users → ci-bot → Change Password
# Update in GitLab: Settings → CI/CD → HARBOR_PASSWORD
# Update on deployment servers: ~/.docker/config.json
# Rotate SSH keys quarterly
```

---

## Security Reminders

1. **Keep admin passwords strong** - GitLab root, Harbor admin
2. **Use HTTPS everywhere** - Even self-signed certs are better than HTTP
3. **Restrict network access** - Firewall rules limit to necessary IPs
4. **Rotate credentials quarterly** - Harbor user passwords, SSH keys
5. **Backup regularly** - Daily backups of GitLab and Harbor
6. **Enable audit logging** - Track who made what changes
7. **Keep systems updated** - Apply security patches promptly

---

## Emergency Procedures

### GitLab down but need to deploy

```bash
# Manual deployment (GitLab not needed)
cd /opt/ai-assistant
docker login harbor.internal:443
docker pull harbor.internal:443/ai-assistant/gateway:latest
docker-compose up -d
```

### Harbor down

```bash
# Use Docker Hub or backup registry temporarily
# Edit docker-compose.yml image references
# Restore from Harbor backup when available
```

### Network connectivity lost

```bash
# Pull last known good images:
docker images | grep harbor.internal

# Services continue to run with cached images
# Restart when network restored
```

---

## Support & References

- **GitLab Docs**: https://docs.gitlab.com/
- **Harbor Docs**: https://goharbor.io/docs/
- **Docker**: https://docs.docker.com/
- **Project Documentation**: See README.md in repository root

For issues, check:
1. Service logs: `docker-compose logs SERVICE_NAME`
2. This guide's troubleshooting section
3. Official documentation for the component
