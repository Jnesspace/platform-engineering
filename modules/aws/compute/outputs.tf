output "id" {
  description = "EC2 instance ID (the primary identifier)."
  value       = aws_instance.this.id
}

output "name" {
  description = "Logical instance name (the Name tag)."
  value       = var.name
}

output "endpoint" {
  description = "Private IP of the instance."
  value       = aws_instance.this.private_ip
}

output "access" {
  description = "How to reach this resource (uniform shape across primitives)."
  value = {
    instance_id       = aws_instance.this.id
    private_ip        = aws_instance.this.private_ip
    public_ip         = aws_instance.this.public_ip
    security_group_id = aws_security_group.this.id
  }
}

# A VM grants nothing to the app role by itself — apps run ON it, they don't
# call the EC2 API. Kept empty on purpose (uniform interface across modules).
output "iam_policy_json" {
  description = "Empty: compute confers no API-level app permissions."
  value       = ""
}
