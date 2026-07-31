# Opinionated small EC2: IMDSv2 required, encrypted gp3 root volume, no public IP, no inbound; ingress is an explicit, 0.0.0.0/0-rejecting input.

# AMI resolved via SSM so it never goes stale in code.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Only looked up when the caller hasn't placed the instance itself.
data "aws_vpc" "default" {
  count = var.vpc_id == null ? 1 : 0

  default = true
}

locals {
  vpc_id = var.vpc_id != null ? var.vpc_id : one(data.aws_vpc.default[*].id)
}

data "aws_subnets" "default" {
  count = var.subnet_id == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  # try() keeps the untaken branch from erroring when the data source isn't instantiated.
  subnet_id = var.subnet_id != null ? var.subnet_id : try(flatten(data.aws_subnets.default[*].ids)[0], null)

  use_cmk = var.kms_key_arn != ""
}

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Minimal SG for ${var.name}: inbound only where explicitly requested"
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules

    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks
  }

  tags = var.tags
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = var.iam_instance_profile

  # Default subnets set map_public_ip_on_launch, so this has to be stated to stay private.
  associate_public_ip_address = var.assign_public_ip

  ebs_optimized           = true
  monitoring              = var.detailed_monitoring
  disable_api_termination = var.disable_api_termination

  # IMDSv2 only: token-less IMDSv1 is the classic SSRF-to-credentials path.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.imds_hop_limit
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted             = true
    kms_key_id            = local.use_cmk ? var.kms_key_arn : null
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
    tags                  = merge(var.tags, { Name = "${var.name}-root" })
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = local.subnet_id != null
      error_message = "No subnet could be resolved: this account has no default VPC with default subnets. Pass var.subnet_id (and var.vpc_id)."
    }
  }
}
