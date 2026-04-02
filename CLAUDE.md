# Claw Builder

Terraform project for provisioning an EC2 instance on AWS, intended as the foundation for a self-hosted AI assistant (OpenClaw).

## Structure

- `terraform/` — all infrastructure-as-code lives here
  - `main.tf` — VPC, subnet, security group, IAM, EC2 instance, Elastic IP, SSH key pair
  - `variables.tf` — configurable inputs (region, instance type, SSH key, etc.)
  - `outputs.tf` — instance ID, static IP, SSH/SSM connect commands
  - `user-data.sh.tpl` — cloud-init script (system updates, swap, auto security updates)
  - `terraform.tfvars` — local-only variable values (gitignored)

## Usage

```bash
cd terraform
terraform init
terraform apply    # bring up
terraform destroy  # tear down
```

## Conventions

- All resources are prefixed with `var.project_name` (default: "claw")
- Keep secrets out of version control — use `terraform.tfvars` (gitignored) for sensitive values like `ssh_public_key`
- SSH access is disabled by default; set `allowed_ssh_cidrs` to enable
- SSH key: uses `~/.ssh/open-claw.pem` locally, imported into AWS via `aws_key_pair`
- The instance uses Ubuntu 24.04 (Noble), IMDSv2 enforced, encrypted EBS
- Design for destroy/recreate — avoid manual state on the instance that can't be reproduced
