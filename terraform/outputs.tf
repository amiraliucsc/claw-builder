output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.main.id
}

output "public_ip" {
  description = "Static public IP (Elastic IP)"
  value       = aws_eip.main.public_ip
}

output "ssm_connect_command" {
  description = "Command to connect via SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.main.id} --region ${var.aws_region}"
}

output "ssh_command" {
  description = "SSH command (only works if allowed_ssh_cidrs is set)"
  value       = "ssh ubuntu@${aws_eip.main.public_ip}"
}

output "instance_type" {
  description = "Current instance type"
  value       = var.instance_type
}

output "availability_zone" {
  description = "AZ the instance is deployed in"
  value       = aws_instance.main.availability_zone
}
