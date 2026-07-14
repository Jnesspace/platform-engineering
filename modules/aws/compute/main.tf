##############################################################################
# compute (AWS) — an opinionated small EC2 instance in the default VPC.
#
# Opinions baked in: t3.micro, latest Amazon Linux 2023 (resolved via SSM so
# the AMI never goes stale in code), default VPC/subnet, and a minimal
# security group: NO inbound, all outbound. Open ingress deliberately, per
# app, outside this module.
##############################################################################

# Always-current AL2023 AMI, resolved at plan time from the public SSM alias.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_vpc" "default" {
  default = true
}

# Default-for-AZ subnets of the default VPC; the instance lands in the first.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Minimal by construction: zero ingress rules, unrestricted egress.
resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Minimal SG for ${var.name}: no inbound, all outbound"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.this.id]

  tags = merge(var.tags, { Name = var.name })
}
