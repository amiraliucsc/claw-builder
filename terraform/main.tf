terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Locals ---

locals {
  agents_map = { for a in var.agents : a.id => a }
  ssm_prefix = "/${var.project_name}"

  openclaw_config = jsonencode({
    gateway = {
      port = 8080
      mode = "local"
      auth = {
        token = "__OPENCLAW_AUTH_TOKEN__"
      }
    }
    models = {
      providers = {
        amazon-bedrock = {
          baseUrl = "https://bedrock-runtime.${var.aws_region}.amazonaws.com"
          auth    = "aws-sdk"
          api     = "bedrock-converse-stream"
          models = [
            {
              id        = "us.anthropic.claude-sonnet-4-6"
              name      = "Claude Sonnet 4.6"
              maxTokens = 8192
            },
            {
              id        = "us.anthropic.claude-opus-4-6-v1"
              name      = "Claude Opus 4.6"
              reasoning = true
              maxTokens = 8192
            },
            {
              id        = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
              name      = "Claude Haiku 4.5"
              maxTokens = 4096
            }
          ]
        }
      }
    }
    agents = {
      defaults = {
        model = {
          primary   = "amazon-bedrock/us.anthropic.claude-sonnet-4-6"
          fallbacks = ["amazon-bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0"]
        }
      }
      list = [for i, a in var.agents : merge(
        { id = a.id },
        i == 0 ? {} : {
          name      = a.name
          workspace = "/home/openclaw/.openclaw/workspace-${a.id}"
          model     = "amazon-bedrock/us.anthropic.claude-sonnet-4-6"
        }
      )]
    }
    channels = {
      telegram = {
        enabled = true
        accounts = { for a in var.agents : a.name => {
          botToken  = "__TELEGRAM_BOT_TOKEN_${a.id}__"
          dmPolicy  = "pairing"
          allowFrom = ["tg:${tostring(a.telegram_user_id)}"]
        } }
      }
    }
    bindings = [for a in var.agents : {
      type    = "route"
      agentId = a.id
      match = {
        channel   = "telegram"
        accountId = a.name
      }
    }]
    tools = {
      web = {
        search = {
          provider = "tavily"
        }
      }
    }
  })
}

# --- Data Sources ---

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_version}-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# --- VPC ---

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group ---

resource "aws_security_group" "instance" {
  name_prefix = "${var.project_name}-"
  description = "${var.project_name} instance security group"
  vpc_id      = aws_vpc.main.id

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # SSH — only if CIDRs are provided
  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
      description = "SSH"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.project_name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- IAM Role ---

resource "aws_iam_role" "instance" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "openclaw" {
  name = "${var.project_name}-openclaw"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMGetParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter${local.ssm_prefix}/*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance.name
}

# --- SSM Parameter Store (secrets) ---

resource "aws_ssm_parameter" "telegram_bot_token" {
  for_each = local.agents_map

  name  = "${local.ssm_prefix}/agents/${each.key}/telegram_bot_token"
  type  = "SecureString"
  value = var.telegram_bot_tokens[each.key]

  tags = { Name = var.project_name }
}

resource "aws_ssm_parameter" "gemini_api_key" {
  name  = "${local.ssm_prefix}/gemini_api_key"
  type  = "SecureString"
  value = var.gemini_api_key

  tags = { Name = var.project_name }
}

resource "aws_ssm_parameter" "tavily_api_key" {
  name  = "${local.ssm_prefix}/tavily_api_key"
  type  = "SecureString"
  value = var.tavily_api_key

  tags = { Name = var.project_name }
}

resource "aws_ssm_parameter" "openclaw_auth_token" {
  name  = "${local.ssm_prefix}/openclaw_auth_token"
  type  = "SecureString"
  value = var.openclaw_auth_token != "" ? var.openclaw_auth_token : "auto"

  tags = { Name = var.project_name }
}

# --- SSH Key Pair ---

resource "aws_key_pair" "main" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key
}

# --- EC2 Instance ---

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  vpc_security_group_ids = [aws_security_group.instance.id]
  key_name               = aws_key_pair.main.key_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    swap_size_gb     = var.swap_size_gb
    project_name     = var.project_name
    aws_region       = var.aws_region
    ssm_prefix       = local.ssm_prefix
    openclaw_config  = local.openclaw_config
    openclaw_version = var.openclaw_version
    agents           = var.agents
  })

  user_data_replace_on_change = true

  tags = {
    Name      = "${var.project_name}-instance"
    ManagedBy = "terraform"
  }
}

# --- Elastic IP (static public IP) ---

resource "aws_eip" "main" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

resource "aws_eip_association" "main" {
  instance_id   = aws_instance.main.id
  allocation_id = aws_eip.main.id
}
