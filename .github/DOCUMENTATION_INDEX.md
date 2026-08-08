# GitLab CE + Harbor Documentation Index

Complete documentation for deploying ai-assistant on a private network with GitLab Community Edition and Harbor Docker Registry.

---

## 📚 Documentation Structure

### 🚀 Quick Start (Start Here!)

**`.github/deployment/QUICK_START.md`** - 30-minute setup guide
- Quick checklist
- 30-minute quick setup
- File structure overview
- Verification steps
- Troubleshooting quick reference

### 🏗️ Infrastructure & Deployment

**`.github/deployment/PRIVATE_NETWORK_DEPLOYMENT.md`** - Complete deployment guide
- Network architecture diagram
- Infrastructure prerequisites (server specs, firewall rules)
- 3-phase deployment process (Weeks 1-3)
- Complete deployment checklist
- Post-deployment operations
- Security hardening checklist

**`docs/gitlab-ce/GITLAB_CE_SETUP.md`** - GitLab CE installation & configuration
- Prerequisites and requirements
- Docker & Docker Compose installation
- SSL/TLS certificate preparation
- GitLab installation steps
- Post-installation setup (group, project, members)
- GitLab runner registration
- Backup & restore procedures
- Network configuration (DNS, SSH, firewall)
- SSL certificate renewal
- Advanced features (SMTP, LDAP, container registry)

**`docs/harbor/HARBOR_SETUP.md`** - Harbor registry setup & management
- Architecture overview
- Prerequisites (hardware, network)
- Harbor installation steps
- Post-installation setup (project, users, permissions)
- Docker login configuration
- Image naming conventions
- Replication policies (disaster recovery)
- Backup & restore procedures
- Monitoring & maintenance
- Vulnerability scanning
- Security hardening

### 🔄 CI/CD Pipeline

**`.gitlab/GITLAB_CI_SETUP.md`** - GitLab CI/CD configuration
- Runner registration (Docker and Shell)
- Harbor registry integration
- Pipeline stages (build, lint, test, publish, deploy)
- `.gitlab-ci.yml` example with all stages
- Helper scripts:
  - `build-image.sh` - Docker image building
  - `push-to-harbor.sh` - Push to Harbor
  - `deploy.sh` - SSH deployment
  - `smoke-test.sh` - Health verification
- CI/CD variables setup
- Branch protection & approval rules
- Merge request workflow & templates
- Pipeline monitoring and troubleshooting

**`.github/registry/HARBOR_REGISTRY.md`** - Harbor registry quick reference
- Registry endpoints (Web UI, Docker API, Harbor API v2.0)
- Example `.gitlab-ci.yml` build & push
- Example `docker-compose.yml` with Harbor
- Authentication setup (docker CLI, deployment servers)
- Image naming conventions with examples
- Vulnerability scanning
- Garbage collection
- Disaster recovery
- Troubleshooting

### ⚙️ Configuration & Environment

**`.github/deployment/.env.template`** - Environment variables template
- GitLab CE configuration
- Harbor registry configuration
- Deployment environment (dev/prod)
- AI Assistant service configuration
- Optional Zabbix monitoring
- Network configuration
- SSL/TLS certificates
- Backup configuration
- Logging & monitoring
- Usage guide
- Security notes
- Quick reference table

### 📋 Setup Automation

**`scripts/gitlab-ci-setup.sh`** - Automated CI/CD setup
- Creates `.gitlab-ci.yml`
- Creates `.gitlab/ci/scripts/` with helper scripts
- Creates merge request template
- Creates `docker-compose.harbor.yml` example
- Provides checklist of next steps

---

## 🎯 Quick Navigation by Task

### "I want to set up GitLab CE"
→ Start: `docs/gitlab-ce/GITLAB_CE_SETUP.md`
- Section 1: Prerequisites & hardware
- Section 2: Docker installation
- Section 3: SSL certificates
- Section 4: Installation steps
- Section 5-10: Post-installation, backup, SSL renewal, LDAP, etc.

### "I want to set up Harbor registry"
→ Start: `docs/harbor/HARBOR_SETUP.md`
- Section 1: Architecture overview
- Section 2-4: Installation steps
- Section 5-10: Post-installation setup
- Section 11-15: Backup, monitoring, troubleshooting

### "I want to deploy ai-assistant to production"
→ Start: `.github/deployment/PRIVATE_NETWORK_DEPLOYMENT.md`
- Network architecture (diagram)
- Infrastructure prerequisites
- Phase 1: Infrastructure (GitLab, Harbor, Runners, Servers)
- Phase 2: Repository setup (import, CI/CD, variables)
- Phase 3: Production deployment
- Complete checklist

### "I want to set up GitLab CI/CD pipeline"
→ Start: `.gitlab/GITLAB_CI_SETUP.md`
- Section 1: Runner setup
- Section 2: Pipeline structure
- Section 3-4: `.gitlab-ci.yml` example
- Section 5: Helper scripts
- Section 6: CI/CD variables
- Section 7: Branch protection

### "I'm in a hurry, give me 30 minutes"
→ Start: `.github/deployment/QUICK_START.md`
- Section 1: Prerequisites
- Section 2: 30-minute quick setup
- Section 3: File structure
- Section 4: Verification steps
- All sections are action-focused, not comprehensive

### "I need to troubleshoot an issue"
→ Start: `.github/deployment/QUICK_START.md` Troubleshooting section
- Then: Check specific service docs
  - GitLab: `docs/gitlab-ce/GITLAB_CE_SETUP.md` → Troubleshooting
  - Harbor: `docs/harbor/HARBOR_SETUP.md` → Troubleshooting
  - CI/CD: `.gitlab/GITLAB_CI_SETUP.md` → Troubleshooting

### "I need to configure environment variables"
→ Start: `.github/deployment/.env.template`
- Copy to `.env.local`
- Fill in your values
- Optionally run `scripts/validate-env.sh`
- Add protected variables to GitLab CI/CD settings

### "I need to push my first Docker image"
→ Start: `.github/registry/HARBOR_REGISTRY.md`
- Section on Harbor authentication
- Section on image naming
- Example push commands

---

## 📖 Document Details

| Document | Path | Size | Sections | Use For |
|----------|------|------|----------|---------|
| Copilot Instructions | `.github/copilot-instructions.md` | 15KB | 10 | AI assistant guidance (general repo) |
| GitLab CE Setup | `docs/gitlab-ce/GITLAB_CE_SETUP.md` | 10KB | 12 | GitLab CE installation & config |
| Harbor Setup | `docs/harbor/HARBOR_SETUP.md` | 10KB | 15 | Harbor registry setup & management |
| GitLab CI/CD Setup | `.gitlab/GITLAB_CI_SETUP.md` | 13KB | 10 | CI/CD pipeline configuration |
| Private Network Deployment | `.github/deployment/PRIVATE_NETWORK_DEPLOYMENT.md` | 10KB | 8 | Complete deployment guide |
| Harbor Registry Ref | `.github/registry/HARBOR_REGISTRY.md` | 4KB | 8 | Quick reference for Harbor |
| Quick Start | `.github/deployment/QUICK_START.md` | 8KB | 10 | 30-minute setup + troubleshooting |
| Environment Template | `.github/deployment/.env.template` | 5KB | 12 | Configuration template |

**Total Documentation: ~75KB, ~100+ sections**

---

## 🔑 Key Concepts

### Architecture Flow
```
Developer
  ↓
GitLab (push)
  ↓
GitLab CI/CD Pipeline
  ├─ Build Docker image
  ├─ Push to Harbor
  └─ Deploy to dev/prod servers
  ↓
Deployment Servers
  ├─ Pull image from Harbor
  └─ Run docker-compose
```

### Network Model
```
Private Network (192.168.1.0/24)
├─ GitLab CE (192.168.1.10)
├─ Harbor Registry (192.168.1.11)
├─ GitLab Runners (192.168.1.30)
├─ Dev Server (192.168.1.100)
└─ Prod Server (192.168.1.101)

All behind firewall; accessible only within network
SSH & HTTPS restricted to admin/service accounts
```

### Security Layers
1. **Network**: Firewall restricts access
2. **Authentication**: Harbor ci-bot, GitLab RBAC
3. **Authorization**: Tool policies, RBAC per role
4. **Audit**: Logging all CI/CD and deployment operations
5. **Secrets**: Masked variables, SSH keys, rotated credentials

---

## ✅ Setup Progression

**Week 1: Infrastructure**
1. Provision 5 servers (GitLab, Harbor, Runner, Dev, Prod)
2. Setup GitLab CE (2-3 hours)
3. Setup Harbor (2-3 hours)
4. Register runners (30 minutes)
5. Verify all systems operational

**Week 2: Repository & CI/CD**
1. Import ai-assistant to GitLab
2. Run `scripts/gitlab-ci-setup.sh`
3. Add CI/CD variables
4. Test pipeline with merge request
5. Verify image in Harbor

**Week 3: Deployment**
1. Deploy to dev environment
2. Run smoke tests
3. Deploy to prod (manual approval)
4. Monitor production
5. Document runbooks

---

## 🔗 Cross-References

### Inside Each Document

- **Top of file**: Quick summary and prerequisites
- **Table of Contents**: Jump to specific sections
- **Cross-links**: References to related documents
- **Code blocks**: Copy-paste ready commands
- **Troubleshooting**: Common issues and solutions
- **Next Steps**: What to do when complete

### Between Documents

- `QUICK_START.md` → Links to full setup guides
- `GITLAB_CI_SETUP.md` → References `.github/registry/HARBOR_REGISTRY.md`
- `PRIVATE_NETWORK_DEPLOYMENT.md` → Links to all component setup guides
- `.env.template` → Used by all services

---

## 📝 File Conventions

### Naming
- Configuration docs end in `_SETUP.md` or `_GUIDE.md`
- Quick references end in `.md` (e.g., `HARBOR_REGISTRY.md`)
- Index/overview files named `INDEX.md` or `README.md`

### Structure
- Every doc starts with title and purpose
- Prerequisites section early
- Numbered steps or sections
- Code blocks with language hints
- Tables for quick reference
- Troubleshooting near end
- References/links at bottom

### Code Examples
```bash
# Commands prefixed with bash
sudo systemctl restart docker

# YAML blocks for config
services:
  gateway:
    image: harbor.internal:443/ai-assistant/gateway:latest
```

---

## 🔄 Maintenance

### Update Schedule

- **Monthly**: Review logs, update certificate renewal dates
- **Quarterly**: Rotate credentials (Harbor, SSH keys)
- **Semi-annually**: Update Harbor/GitLab to latest stable version
- **Yearly**: Review disaster recovery procedures, test restore

### Backups

- **GitLab**: Daily automated backups (configured in setup)
- **Harbor**: Daily automated backups (configured in setup)
- **Deployment configs**: Stored in Git (automatically versioned)

### Monitoring

- **Pipeline health**: Check GitLab Pipelines dashboard weekly
- **Disk usage**: Monitor on all servers monthly
- **Certificate expiry**: Set calendar reminders for renewal dates
- **Error rates**: Review logs for anomalies

---

## 🆘 Support

### For Issues

1. **Check Quick Start** → `QUICK_START.md` Troubleshooting section
2. **Check Relevant Setup Guide** → Full troubleshooting section
3. **Check Official Docs**:
   - GitLab: https://docs.gitlab.com/
   - Harbor: https://goharbor.io/docs/
   - Docker: https://docs.docker.com/

### For Questions

Refer to:
- Specific document's "Next Steps" section
- `.github/copilot-instructions.md` for general development guidance
- ROADMAP.md for project direction

---

## 📋 Checklist for Completion

After working through all documentation:

- [ ] All servers provisioned (GitLab, Harbor, Runner, Dev, Prod)
- [ ] GitLab CE running at https://gitlab.internal/
- [ ] Harbor running at https://harbor.internal/
- [ ] ai-assistant repository in GitLab
- [ ] `.gitlab-ci.yml` configured
- [ ] CI/CD variables added
- [ ] Runner registered and healthy
- [ ] Images pushing to Harbor
- [ ] Deployment to dev successful
- [ ] Smoke tests passing
- [ ] Deployment to prod configured (manual approval)
- [ ] Backups automated
- [ ] Team trained on deployment process

---

**Version:** 1.0  
**Last Updated:** 2026-08-08  
**Repository:** gave-partake-unwed/ai-assistant  
**For:** Private network deployment with GitLab CE + Harbor
