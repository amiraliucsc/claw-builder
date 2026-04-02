variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "claw"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "ubuntu_version" {
  description = "Ubuntu version filter for AMI lookup (e.g. noble-24.04, jammy-22.04)"
  type        = string
  default     = "noble-24.04"
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH. Empty list disables SSH ingress entirely."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Name for the AWS key pair"
  type        = string
  default     = "open-claw"
}

variable "ssh_public_key" {
  description = "SSH public key material (run: ssh-keygen -y -f ~/.ssh/open-claw.pem)"
  type        = string
}

variable "swap_size_gb" {
  description = "Swap file size in GB (0 to disable)"
  type        = number
  default     = 2
}

# --- OpenClaw ---

variable "agents" {
  description = "List of OpenClaw agents. Each gets its own Telegram bot, workspace, and user binding."
  type = list(object({
    id               = string
    name             = string
    telegram_user_id = number
  }))

  validation {
    condition     = length(var.agents) > 0
    error_message = "At least one agent must be defined."
  }

  validation {
    condition     = length(var.agents) == length(distinct([for a in var.agents : a.id]))
    error_message = "Agent IDs must be unique."
  }

  validation {
    condition     = alltrue([for a in var.agents : can(regex("^[a-z][a-z0-9_]*$", a.id))])
    error_message = "Agent IDs must start with a lowercase letter and contain only lowercase letters, digits, and underscores."
  }
}

variable "telegram_bot_tokens" {
  description = "Map of agent ID to Telegram bot token. Must have an entry for each agent."
  type        = map(string)
  sensitive   = true
}

variable "gemini_api_key" {
  description = "Google Gemini API key for memory/embeddings"
  type        = string
  sensitive   = true
}

variable "tavily_api_key" {
  description = "Tavily API key for web search"
  type        = string
  sensitive   = true
}

variable "openclaw_auth_token" {
  description = "OpenClaw gateway auth token (leave empty to auto-generate at boot)"
  type        = string
  sensitive   = true
  default     = ""
}
