# Claw Builder

One-click Terraform deployment of OpenClaw (self-hosted AI assistant) on AWS EC2 with multi-agent support.

## Structure

- `terraform/` — all infrastructure-as-code
  - `main.tf` — VPC, SG, IAM, SSM secrets, EC2, Elastic IP, openclaw.json config (jsonencode in locals)
  - `variables.tf` — all configurable inputs
  - `outputs.tf` — instance info, URLs, connect commands
  - `user-data.sh.tpl` — cloud-init: installs OpenClaw, nginx, configures multi-agent gateway
  - `terraform.tfvars` — your secrets (gitignored, never committed)
  - `terraform.tfvars.example` — template showing required variables

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars  # fill in your values
terraform init
terraform apply    # deploy everything
terraform destroy  # tear down
```

## What `terraform apply` Does

1. Creates AWS infra: VPC, subnet, IGW, security group, IAM role (SSM + Bedrock), EC2 instance, Elastic IP
2. Stores secrets in SSM Parameter Store (encrypted)
3. EC2 boots and runs user-data.sh which:
   - Installs Node.js 22, AWS CLI v2, nginx, unattended-upgrades
   - Creates 2GB swap (critical for t3.small)
   - Installs pinned OpenClaw version via `npm install -g openclaw@<version>`
   - Creates `openclaw` system user
   - Pulls all secrets from SSM Parameter Store
   - Builds `openclaw.json` config (replaces token placeholders via jq)
   - Creates per-agent workspaces + shared memory directory with symlinks
   - Writes `.env` with API keys
   - Creates and starts systemd service (hardened)
   - Configures nginx reverse proxy (self-signed cert, 443 → 8080)
4. OpenClaw gateway starts, connects Telegram bots, begins accepting messages

## Secrets Flow

```
terraform.tfvars (local only, gitignored)
  → Terraform stores in SSM Parameter Store (encrypted)
    → EC2 user-data pulls from SSM at boot
      → Writes openclaw.json + .env (never in repo or TF state plaintext)
```

SSM parameter hierarchy: `/<project_name>/gemini_api_key`, `/<project_name>/agents/<id>/telegram_bot_token`, etc.

## Multi-Agent Architecture

- Single OpenClaw gateway process handles all agents
- Each agent defined in the `agents` variable gets:
  - Its own Telegram bot (separate token from @BotFather)
  - Its own workspace directory
  - Its own `allowFrom` user ID binding
- Routing: Telegram account → binding → agent
- Shared memory: symlinked directory accessible to all agents
- First agent uses the default workspace; additional agents get `workspace-<id>`

## Conventions

- All resources prefixed with `var.project_name` (default: "claw")
- Secrets go in `terraform.tfvars` only — never in committed files
- SSH disabled by default; set `allowed_ssh_cidrs` to enable
- SSH key: `~/.ssh/open-claw.pem` locally, imported via `aws_key_pair`
- Ubuntu 24.04 (Noble), IMDSv2 enforced, encrypted EBS
- OpenClaw version is pinned via `openclaw_version` variable (default: 2026.4.1)
- `user_data_replace_on_change = true` — changing agents or config triggers instance replacement
- Design for destroy/recreate — all state lives in SSM + Terraform, not on the instance

## Current Deployment Status

- OpenClaw 2026.4.1 on t3.small, us-west-2
- Static IP: Elastic IP (persists across instance replacements)
- One agent deployed: "Sally" (agent ID: `main`)
- Bedrock models: Claude Sonnet 4.6, Opus 4.6, Haiku 4.5
- Telegram bot connected and responding
- Nginx HTTPS reverse proxy returning 200
- Control UI accessible at `https://<EIP>` with auto-generated auth token
- `controlUi.allowedOrigins` automatically set to the Elastic IP
- Auth token is auto-generated at boot if `openclaw_auth_token` is left empty in tfvars (changes on every instance rebuild)

## Gotchas / Lessons Learned

- OpenClaw 2026.4.1 does NOT recognize `memorySearch` in tools or `autoFlush`/`directories`/`enabled`/`softThresholdTokens` in memory config — these cause the gateway to crash with "Config invalid"
- The `gateway.mode` must be `"local"` or the gateway refuses to start
- `npm install -g openclaw` must run as root, not as the openclaw user
- jq `to_entries[] |= ` path expressions don't work for in-place updates on object values — use `walk` instead for placeholder replacement
- EC2 host key changes on every instance replacement — SSH will warn about MITM; clear with `ssh-keygen -R <ip>`
- Terraform `sensitive = true` on a variable prevents using it in `for_each` — separate sensitive fields (tokens) from non-sensitive fields (IDs, names)

## Known Limitations / Future Work

- No agent personality files (USER.md, IDENTITY.md) — agents have no context about the user yet
- No mTLS on nginx (currently self-signed cert only)
- No Hindsight memory server (would need Docker + EBS data volume + OpenAI key)
- No proactive agent system (morning/evening briefings, alerts)
- No Asana/Gmail/Calendar integrations
- Auth token not persistent across rebuilds unless set explicitly in tfvars
- Memory/embedding features not configured (Gemini key is deployed but not wired into OpenClaw config yet)
