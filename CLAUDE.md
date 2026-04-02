# Claw Builder

One-click Terraform deployment of OpenClaw (self-hosted AI assistant) on AWS EC2 with multi-agent support.

## Structure

- `terraform/` — all infrastructure-as-code
  - `main.tf` — VPC, SG, IAM, SSM secrets, EC2, Elastic IP
  - `variables.tf` — all configurable inputs
  - `outputs.tf` — instance info, URLs, connect commands
  - `user-data.sh.tpl` — cloud-init: installs OpenClaw, configures multi-agent gateway
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
- `user_data_replace_on_change = true` — changing agents triggers instance replacement
- Design for destroy/recreate — all state lives in SSM + Terraform, not on the instance
