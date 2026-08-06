LiteLLM quickstart (project folder)

This folder contains a small docker-compose setup to run LiteLLM with a backing Postgres DB. Follow these steps to configure and start the service.

Prerequisites
- Docker and docker-compose installed (v2)
- A user account with permission to run docker commands
- A Docker network named `management_network` if you plan to integrate with other services. Create it with:

  docker network create management_network

1) Create .env from the example

  cp projects/litellm/.env.example projects/litellm/.env
  # Edit projects/litellm/.env and replace the placeholders with secure values:
  # - LITELLM_MASTER_KEY: 32+ byte hex or base64 string
  # - LITELLM_SALT_KEY: a long random string
  # - DATABASE_URL: leave as-is if using the bundled `db` service
  # - LITELLM_API_KEY: create a virtual key and paste it here (see step 4)

Security note: Never commit `.env` to version control. Use a secrets manager for production.

2) Start the LiteLLM stack

  docker compose -f projects/litellm/docker-compose.yml --env-file projects/litellm/.env up -d

3) Check service health

  # LiteLLM HTTP port (4000) should be reachable
  curl -v http://localhost:4000/health

  # Database
  docker compose -f projects/litellm/docker-compose.yml exec db pg_isready -U litellm

4) Create a virtual API key (recommended)

LiteLLM supports the concept of API/virtual keys. You can create an integration key and store it in your `.env` for other services (for local dev only). Replace the example values below with your own.

Example (replace values and run from a terminal once the service is up):

  curl -X POST "http://localhost:4000/v1/keys" \
    -H "Content-Type: application/json" \
    -d '{ "name": "n8n-integration", "scopes": ["chat:read","chat:write"] }'

The exact endpoint depends on your LiteLLM version. If the above returns a 401 or not found, consult the LiteLLM docs for the admin API for key creation.

5) Wire the key into n8n / gateway

- In n8n, add credentials or environment variables that reference the LITELLM_API_KEY value and use it when calling http://litellm:4000/v1/chat/completions. For the Next step, see the n8n workflow `02-planner.json` which calls the local LiteLLM endpoint.

6) Troubleshooting

- If the `litellm` container exits or fails healthcheck, inspect logs:
  docker compose -f projects/litellm/docker-compose.yml logs litellm --tail 200

- If Postgres doesn't start, inspect DB logs and ensure the `postgres_data` volume is writable.

7) Production considerations

- Rotate LITELLM_MASTER_KEY and LITELLM_SALT_KEY before attaching real data.
- Use a managed Postgres for production or configure backups for the local volume.
- Configure TLS, authentication, and firewalling when exposing the service publicly.
- Use Docker secrets, HashiCorp Vault, AWS Secrets Manager, or Kubernetes Secrets to store production secrets.

If you want, I can:
- Create a small script to programmatically create virtual keys and store them in your `.env` (local-only helper),
- Add a Kubernetes manifest for LiteLLM, or
- Add an n8n credential template for the LiteLLM API key and show how to store it securely in n8n.
