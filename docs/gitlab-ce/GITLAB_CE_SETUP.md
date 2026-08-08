# GitLab CE Setup & Configuration

Complete setup guide for self-hosted GitLab Community Edition with ai-assistant repository.

---

## GitLab CE Installation

### Prerequisites

- Linux server (Ubuntu 20.04 LTS or later recommended)
- 4+ CPU cores
- 8+ GB RAM
- 50+ GB disk space (adjust based on repository size)
- Network access for SSH (port 22) and HTTPS (port 443)
- SSL/TLS certificate (self-signed or CA-signed)

### Installation Steps

#### 1. Install Docker & Docker Compose

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add current user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify
docker --version && docker-compose --version
```

#### 2. Prepare SSL Certificates

For HTTPS (highly recommended):

```bash
# Option A: Self-signed certificate (internal use)
mkdir -p /opt/gitlab/ssl
cd /opt/gitlab/ssl

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout gitlab.internal.key \
  -out gitlab.internal.crt \
  -subj "/CN=gitlab.internal"

# Option B: Use existing CA-signed certificate
# cp /path/to/gitlab.internal.crt /opt/gitlab/ssl/
# cp /path/to/gitlab.internal.key /opt/gitlab/ssl/

# Set permissions
sudo chmod 600 /opt/gitlab/ssl/*
```

#### 3. Create docker-compose.yml for GitLab

```yaml
version: '3.6'

services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: always
    hostname: gitlab.internal
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://gitlab.internal'
        nginx['ssl_certificate'] = '/etc/gitlab/ssl/gitlab.internal.crt'
        nginx['ssl_certificate_key'] = '/etc/gitlab/ssl/gitlab.internal.key'
        nginx['ssl_protocols'] = "TLSv1.2 TLSv1.3"
        gitlab_rails['gitlab_shell_ssh_port'] = 2222
        gitlab_rails['initial_root_password'] = 'STRONG_ROOT_PASSWORD'
        gitlab_rails['signup_enabled'] = false
        postgresql['max_connections'] = 200
        postgresql['shared_buffers'] = "256MB"
        redis['maxmemory'] = "256mb"
        puma['worker_processes'] = 2
        gitlab_workhorse['max_conn'] = 10
    ports:
      - "443:443"
      - "80:80"
      - "2222:22"
    volumes:
      - gitlab_config:/etc/gitlab
      - gitlab_logs:/var/log/gitlab
      - gitlab_data:/var/opt/gitlab
      - /opt/gitlab/ssl:/etc/gitlab/ssl:ro
    networks:
      - gitlab

  # Optional: GitLab Runner
  gitlab-runner:
    image: gitlab/gitlab-runner:latest
    container_name: gitlab-runner
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - gitlab_runner_config:/etc/gitlab-runner
    networks:
      - gitlab
    depends_on:
      - gitlab

volumes:
  gitlab_config:
  gitlab_logs:
  gitlab_data:
  gitlab_runner_config:

networks:
  gitlab:
    driver: bridge
```

#### 4. Launch GitLab

```bash
mkdir -p /opt/gitlab/ssl
cd /opt/gitlab

# Copy docker-compose.yml from above

# Start services
docker-compose up -d

# Wait for GitLab to initialize (can take 5-10 minutes)
docker-compose logs -f gitlab

# Verify access
# https://gitlab.internal/
# Default credentials: root / STRONG_ROOT_PASSWORD
```

---

## Post-Installation Configuration

### 1. Initial Setup

1. Access https://gitlab.internal/ (accept SSL warning if self-signed)
2. Log in: `root` / `STRONG_ROOT_PASSWORD`
3. Go to **Admin Area** (wrench icon) → **Settings**

### 2. Configure System

**Admin → Settings → General → Account and limit:**
- Sign-up enabled: ❌ (disable for internal use)
- Sign-up restrictions: `@internal.local` (domain allowlist)
- Session duration: 1 week

**Admin → Settings → Security & Compliance:**
- Enable personal access tokens: ✅
- Allow local requests from web hooks: ✅
- Restrict web hook to IP whitelist: ✅ (add runner IPs)

### 3. Create ai-assistant Group & Project

#### A. Create Group

**Groups → New Group:**

```
Group name: ai-assistant
Group slug: ai-assistant
Visibility: Private
Description: AI Assistant operational platform
```

#### B. Create Project

**Projects → New Project:**

```
Project name: ai-assistant
Project slug: ai-assistant
Visibility: Private
Description: Core ai-assistant repository
CI/CD visibility: Enabled
Default branch: main
README: Include
License: Apache-2.0 (or your choice)
Gitignore: Python
```

#### C. Add Group Members

**Groups → ai-assistant → Members → Invite members:**

Assign roles:
- Owner: You (admin)
- Maintainer: DevOps/Infrastructure team
- Developer: Development team
- Guest: External stakeholders (if any)

---

## GitLab Runner Registration

### Docker Runner (Recommended)

```bash
# Inside gitlab-runner container
docker exec -it gitlab-runner gitlab-runner register \
  --url https://gitlab.internal/ \
  --registration-token PROJECT_REGISTRATION_TOKEN \
  --executor docker \
  --docker-image docker:latest \
  --docker-privileged \
  --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
  --tag-list "docker,linux,ai-assistant" \
  --run-untagged=false \
  --locked=false \
  --name "ai-assistant-docker-runner"

# Restart runner
docker-compose restart gitlab-runner
```

To find `PROJECT_REGISTRATION_TOKEN`:
1. Go to **Projects → ai-assistant → Settings → CI/CD → Runners**
2. Copy the registration token

### Verify Runner

```bash
# Check if runner is active
docker exec gitlab-runner gitlab-runner verify

# View runner config
docker exec gitlab-runner cat /etc/gitlab-runner/config.toml
```

---

## Harbor Integration in GitLab

### Configure Package Registry (Optional)

If using GitLab's built-in Docker Registry instead of Harbor:

**Group → ai-assistant → Settings → Package and registries:**

- Container registry: Enabled ✅
- Access level: Private

### Use Harbor Registry (Recommended)

Instead, configure Harbor credentials in GitLab CI/CD variables (see `.gitlab/GITLAB_CI_SETUP.md`):

```
HARBOR_REGISTRY=harbor.internal:443
HARBOR_PROJECT=ai-assistant
HARBOR_USER=ci-bot
HARBOR_PASSWORD=<strong-password>
```

---

## Backup & Restore

### Automated Backup

Add to crontab:

```bash
0 2 * * * docker exec gitlab /opt/gitlab/bin/gitlab-backup create STRATEGY=copy

# Keep only last 7 backups
0 3 * * * find /var/opt/gitlab/backups -maxdepth 1 -name "*.tar" -mtime +7 -delete
```

### Manual Backup

```bash
# Create backup
docker exec gitlab /opt/gitlab/bin/gitlab-backup create STRATEGY=copy

# Backup location
ls -la /var/opt/gitlab/backups/

# Store offsite (example: rsync to backup server)
rsync -av /var/opt/gitlab/backups/ backup-server:/backup/gitlab/
```

### Restore

```bash
# Stop GitLab services
docker exec gitlab /opt/gitlab/bin/gitlab-ctl stop unicorn
docker exec gitlab /opt/gitlab/bin/gitlab-ctl stop sidekiq

# Restore from backup
docker exec gitlab /opt/gitlab/bin/gitlab-backup restore BACKUP=TIMESTAMP

# Start GitLab
docker exec gitlab /opt/gitlab/bin/gitlab-ctl restart

# Verify
docker-compose logs gitlab
```

---

## Network Configuration

### DNS Setup

Add to your internal DNS or `/etc/hosts`:

```
192.168.1.10  gitlab.internal
192.168.1.10  harbor.internal
192.168.1.10  gateway-dev.internal
192.168.1.10  gateway-prod.internal
```

(Adjust IPs to match your network)

### SSH Configuration

For SSH-based Git operations:

**On each developer machine:**

```bash
# ~/.ssh/config
Host gitlab.internal
  HostName gitlab.internal
  Port 2222
  User git
  IdentityFile ~/.ssh/id_rsa
```

Then clone via SSH:

```bash
git clone ssh://git@gitlab.internal/ai-assistant/ai-assistant.git
```

### Firewall Rules

```bash
# Allow necessary ports (example for UFW)
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 2222/tcp    # GitLab SSH

# Restrict to specific networks (optional)
sudo ufw allow from 192.168.1.0/24 to any port 443
```

---

## SSL/TLS Certificate Renewal

### Self-Signed Certificates (Valid for 1 year)

Before expiration, regenerate:

```bash
cd /opt/gitlab/ssl

# Backup old certs
cp gitlab.internal.crt gitlab.internal.crt.bak
cp gitlab.internal.key gitlab.internal.key.bak

# Generate new certificate
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout gitlab.internal.key \
  -out gitlab.internal.crt \
  -subj "/CN=gitlab.internal"

# Restart GitLab
cd /opt/gitlab
docker-compose restart gitlab
```

### CA-Signed Certificates (Renewal as needed)

Follow your CA's renewal process and update:
- `/opt/gitlab/ssl/gitlab.internal.crt`
- `/opt/gitlab/ssl/gitlab.internal.key`

Then restart GitLab.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| GitLab not starting | Check logs: `docker-compose logs gitlab`; ensure sufficient disk/RAM |
| SSL certificate warning | Add cert to system trust: `sudo cp gitlab.internal.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates` |
| Runner not connecting | Check registration token is correct, verify network connectivity, restart runner |
| High memory usage | Increase swap, reduce puma workers, enable object storage |
| Slow Git operations | Check network bandwidth, enable Git protocol v2 |

---

## Advanced Configuration

### SMTP for Email Notifications

In `docker-compose.yml`, add:

```yaml
environment:
  GITLAB_OMNIBUS_CONFIG: |
    # ... existing config ...
    gitlab_rails['smtp_enable'] = true
    gitlab_rails['smtp_address'] = "mail.internal.local"
    gitlab_rails['smtp_port'] = 25
    gitlab_rails['smtp_domain'] = "internal.local"
    gitlab_rails['gitlab_email_from'] = "gitlab@internal.local"
```

### LDAP/Active Directory Integration

If your organization uses LDAP:

**Admin Area → Settings → Authentication:**

- LDAP Server: `ldap.internal.local`
- Base DN: `dc=internal,dc=local`
- Bind DN: `cn=gitlab,dc=internal,dc=local`

### Enable Container Registry (Optional)

For using GitLab's built-in Docker Registry instead of Harbor:

```yaml
environment:
  GITLAB_OMNIBUS_CONFIG: |
    # ... existing config ...
    registry['enable'] = true
    registry['storage'] = { 's3' => { 'bucket' => 'gitlab-registry' } }
```

---

## References

- GitLab CE Installation: https://docs.gitlab.com/ee/install/
- Docker Installation: https://docs.gitlab.com/ee/install/docker.html
- GitLab Runner: https://docs.gitlab.com/runner/
- GitLab CI/CD: https://docs.gitlab.com/ee/ci/
- SSL Configuration: https://docs.gitlab.com/omnibus/settings/ssl.html
