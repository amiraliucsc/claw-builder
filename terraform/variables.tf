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
