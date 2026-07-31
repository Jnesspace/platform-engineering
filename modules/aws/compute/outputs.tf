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
  description = "How to reach this resource (uniform shape across primitives). public_ip is empty unless assign_public_ip is on."
  value = {
    instance_id       = aws_instance.this.id
    private_ip        = aws_instance.this.private_ip
    public_ip         = aws_instance.this.public_ip
    security_group_id = aws_security_group.this.id
    subnet_id         = aws_instance.this.subnet_id
  }
}

# Empty on purpose: apps run ON the VM, not against the EC2 API (uniform interface).
# A CMK root volume does not change this — EC2 decrypts the volume with its own service grant, not the app role.
output "iam_policy_json" {
  description = "Empty: compute confers no API-level app permissions."
  value       = ""
}
