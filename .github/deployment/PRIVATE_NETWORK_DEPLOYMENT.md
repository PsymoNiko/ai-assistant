# Private Network Deployment Guide

Complete guide for deploying ai-assistant on a private network with GitLab CE and Harbor.

---

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Private Network (192.168.1.0/24)          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐ │
│  │  GitLab CE       │  │  Harbor Registry │  │   Zabbix   │ │
│  │  192.168.1.10    │  │  192.168.1.11    │  │192.168.1.20│ │
│  │  Port: 443, 2222 │  │  Port: 443       │  │ Port: 80   │ │
│  └──────────────────┘  └──────────────────┘  └────────────┘ │
│          ↓ SSH                     ↑                          │
│          ↓ Push/Pull               ↑ Pull Images              │
│  ┌──────────────────────────────────────────┐                │
│  │    GitLab Runner                         │                │
│  │    192.168.1.30                          │                │
│  │    Docker Executor                       │                │
│  └──────────────────────────────────────────┘                │
│          ↓ SSH Deploy                                        │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │  Dev Server      │  │  Prod Server     │                 │
│  │  192.168.1.100   │  │  192.168.1.101   │                 │
│  │  ├─ Gateway      │  │  ├─ Gateway      │                 │
│  │  ├─ n8n          │  │  ├─ n8n          │                 │
│  │  ├─ Postgres     │  │  ├─ Postgres     │                 │
│  │  └─ Redis        │  │  └─ Redis        │                 │
│  └──────────────────┘  └──────────────────┘                 │
│                                                               │
│  Firewall Rules: Only allow:                                 │
│  - SSH (22) from admin/deploy subnet                         │
│  - HTTPS (443) for web access                                │
│  - Docker push/pull (Harbor only from runners/servers)       │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Infrastructure Prerequisites

### 1. Network Planning

| Component | IP | Hostname | Port | Notes |
|-----------|----|----|------|-------|
| GitLab CE | 192.168.1.10 | gitlab.internal | 443, 2222 | Central CI/CD hub |
| Harbor | 192.168.1.11 | harbor.internal | 443 | Private Docker registry |
| Zabbix | 192.168.1.20 | zabbix.internal | 80, 10051 | Monitoring (optional) |
| Runner | 192.168.1.30 | runner.internal | - | GitLab CI executor |
| Dev Server | 192.168.1.100 | dev-server.internal | 8080 | Development environment |
| Prod Server | 192.168.1.101 | prod-server.internal | 8080 | Production environment |

**DNS / /etc/hosts:**

```
192.168.1.10  gitlab.internal  gitlab
192.168.1.11  harbor.internal  harbor
192.168.1.20  zabbix.internal  zabbix
192.168.1.30  runner.internal  runner
192.168.1.100 dev-server.internal dev-server
192.168.1.101 prod-server.internal prod-server
```

### 2. Server Specifications

| Server | CPU | RAM | Disk | OS |
|--------|-----|-----|------|-----|
| GitLab | 4+ | 8GB+ | 50GB+ | Ubuntu 20.04 LTS |
| Harbor | 2+ | 4GB+ | 100GB+ | Ubuntu 20.04 LTS |
| Runner | 4+ | 8GB+ | 50GB+ | Ubuntu 20.04 LTS |
| Dev | 2+ | 4GB+ | 20GB+ | Ubuntu 20.04 LTS |
| Prod | 4+ | 8GB+ | 50GB+ | Ubuntu 20.04 LTS |

### 3. Firewall Configuration

```bash
# On each server, enable UFW
sudo ufw enable

# GitLab Server
sudo ufw allow from 192.168.1.0/24 to any port 443  # HTTPS
sudo ufw allow from 192.168.1.0/24 to any port 2222 # Git SSH
sudo ufw allow from 192.168.1.30 to any port 443    # Runner access

# Harbor Server
sudo ufw allow from 192.168.1.30 to any port 443    # Runner push/pull
sudo ufw allow from 192.168.1.100 to any port 443   # Dev pull
sudo ufw allow from 192.168.1.101 to any port 443   # Prod pull

# Runner Server
sudo ufw allow from 192.168.1.10 to any port 22     # GitLab connection

# Deployment Servers
sudo ufw allow from 192.168.1.30 to any port 22     # Runner SSH deploy
sudo ufw allow 8080/tcp                              # Gateway port

# SSH access (from admin machines only)
sudo ufw allow from 192.168.1.50 to any port 22
```

---

## Deployment Process

### Phase 1: Infrastructure Setup (Week 1)

**Day 1: GitLab CE**
1. Provision server (192.168.1.10)
2. Follow `docs/gitlab-ce/GITLAB_CE_SETUP.md`
3. Configure DNS/SSL
4. Verify access: https://gitlab.internal/

**Day 2: Harbor Registry**
1. Provision server (192.168.1.11)
2. Follow `docs/harbor/HARBOR_SETUP.md`
3. Configure SSL
4. Create `ai-assistant` project and `ci-bot` user
5. Verify access: https://harbor.internal/

**Day 3: GitLab Runner**
1. Provision server (192.168.1.30)
2. Install Docker and Docker Compose
3. Register Docker runner with GitLab CE
4. Test runner connectivity in GitLab UI
5. Configure Harbor login credentials

**Day 4-5: Deployment Servers**
1. Provision dev server (192.168.1.100)
2. Provision prod server (192.168.1.101)
3. Install Docker and Docker Compose
4. Setup SSH keys for GitLab CI/CD deployment
5. Configure Harbor login credentials

### Phase 2: Repository Setup (Week 2)

**Day 1: Import ai-assistant Repository**

```bash
# On a local machine with network access
git clone https://github.com/original/ai-assistant.git
cd ai-assistant

# Add GitLab remote
git remote add gitlab ssh://git@gitlab.internal:2222/ai-assistant/ai-assistant.git

# Push to GitLab CE
git push -u gitlab main
git push -u gitlab develop
```

**Day 2: Configure CI/CD**

1. Copy `.gitlab-ci.yml` from `.gitlab/GITLAB_CI_SETUP.md` to repository root
2. Create `.gitlab/ci/scripts/` directory with helper scripts
3. Create `.gitlab/merge_request_templates/`
4. Commit and push

**Day 3: Setup CI/CD Variables**

In GitLab: **Projects → ai-assistant → Settings → CI/CD → Variables**

Add (see `.gitlab/GITLAB_CI_SETUP.md` for full list):
- `HARBOR_REGISTRY`: harbor.internal:443
- `HARBOR_PROJECT`: ai-assistant
- `HARBOR_USER`: ci-bot
- `HARBOR_PASSWORD`: <masked>
- SSH keys for dev/prod deployment

**Day 4-5: Test Pipeline**

1. Create test merge request
2. Verify pipeline runs through all stages
3. Check image push to Harbor
4. Test deployment to dev environment
5. Verify smoke tests pass

### Phase 3: Production Deployment (Week 3)

**Day 1: Load Testing**
- Deploy to dev with sample data
- Verify all services operational
- Test end-to-end workflow

**Day 2-3: Cutover**
- Prepare rollback procedure
- Deploy to production
- Verify production health checks pass

---

## Deployment Checklist

### Pre-Deployment

- [ ] All servers provisioned and networked
- [ ] DNS entries configured
- [ ] SSL certificates installed (self-signed OK for internal)
- [ ] GitLab CE running and accessible
- [ ] Harbor setup complete with ci-bot user
- [ ] Runner registered and passing health checks
- [ ] SSH keys configured for deployment servers
- [ ] Firewall rules in place

### GitLab & Harbor

- [ ] ai-assistant group created in GitLab
- [ ] ai-assistant project created in GitLab
- [ ] Repository imported/pushed to GitLab
- [ ] .gitlab-ci.yml configured
- [ ] CI/CD variables set
- [ ] ai-assistant project created in Harbor
- [ ] ci-bot user created and assigned to project
- [ ] Runner can login to Harbor

### CI/CD Pipeline

- [ ] Lint stage passes
- [ ] Build stage creates Docker image
- [ ] Image pushed to Harbor successfully
- [ ] Dev deployment successful
- [ ] Smoke tests pass on dev
- [ ] Prod deployment manual approval configured
- [ ] Merge request template configured

### Deployment Servers

- [ ] Dev server can pull from Harbor
- [ ] Prod server can pull from Harbor
- [ ] SSH deployment keys configured
- [ ] docker-compose.yml updated with Harbor image references
- [ ] Environment variables configured (.env files)
- [ ] Services running and accessible

### Monitoring

- [ ] Zabbix monitoring configured (optional)
- [ ] Alert thresholds set
- [ ] Backup procedures documented
- [ ] Runbook for common issues created

---

## Post-Deployment Operations

### Daily Operations

```bash
# Check service health
docker-compose ps
docker-compose logs -f gateway

# Verify Harbor images are available
curl -u ci-bot:password https://harbor.internal/api/v2.0/projects

# Monitor disk usage
df -h /data/harbor
df -h /var/opt/gitlab
```

### Backup Schedule

- **GitLab**: Daily backups (automated via cron)
- **Harbor**: Daily backups (automated via cron)
- **Deployment data**: As needed (database/configs)

### Monitoring & Alerts

Monitor these metrics:
- GitLab UI response time
- Harbor image push/pull latency
- Disk usage on all servers
- Docker container health
- Network connectivity between servers

---

## Troubleshooting Common Issues

### Pipeline fails to authenticate with Harbor

```bash
# Check Harbor credentials in GitLab CI variables
# Verify Harbor user exists: https://harbor.internal/
# Test login manually on runner:
docker login harbor.internal:443 -u ci-bot -p <password>
```

### SSH deployment fails

```bash
# Verify SSH key is in GitLab CI variable
# Test SSH connectivity:
ssh -i /path/to/deploy_key deploy@dev-server.internal "docker-compose ps"
# Check ~/.ssh/authorized_keys on deployment server
```

### Docker image layers cached incorrectly

```bash
# Force rebuild without cache
# In .gitlab-ci.yml, add:
# script:
#   - docker build --no-cache -t image:tag .
```

### GitLab Runner not picking up jobs

```bash
# Verify runner is running
docker exec gitlab-runner gitlab-runner verify

# Check runner tags match CI/CD job tags
# View runner config:
docker exec gitlab-runner cat /etc/gitlab-runner/config.toml

# Restart runner
docker-compose restart gitlab-runner
```

---

## Security Hardening Checklist

- [ ] SSH key access restricted to admin subnet
- [ ] All services use HTTPS (even self-signed)
- [ ] Firewall rules restrict traffic to necessary ports only
- [ ] Database passwords changed from defaults
- [ ] GitLab root password changed
- [ ] Harbor admin password changed
- [ ] CI/CD secrets marked as masked in GitLab
- [ ] Regular security updates applied
- [ ] Backup encryption enabled
- [ ] Audit logs reviewed periodically

---

## References

- Complete setup guides are in:
  - `docs/gitlab-ce/GITLAB_CE_SETUP.md`
  - `docs/harbor/HARBOR_SETUP.md`
  - `.gitlab/GITLAB_CI_SETUP.md`
- Network security: Linux UFW firewall rules
- SSL/TLS: Self-signed certificates or CA-signed
- Docker networking: Compose v3 networks
