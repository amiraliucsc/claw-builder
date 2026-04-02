output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.main.id
}

output "public_ip" {
  description = "Static public IP (Elastic IP)"
  value       = aws_eip.main.public_ip
}

output "openclaw_url" {
  description = "OpenClaw gateway URL (self-signed cert)"
  value       = "https://${aws_eip.main.public_ip}"
}

output "agent_names" {
  description = "Deployed agent names"
  value       = [for a in var.agents : a.name]
}

output "ssm_connect_command" {
  description = "Command to connect via SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.main.id} --region ${var.aws_region}"
}

output "ssh_command" {
  description = "SSH command (only works if allowed_ssh_cidrs is set)"
  value       = "ssh -i ~/.ssh/open-claw.pem ubuntu@${aws_eip.main.public_ip}"
}

output "setup_log_command" {
  description = "SSH command to tail the instance setup log"
  value       = "ssh -i ~/.ssh/open-claw.pem ubuntu@${aws_eip.main.public_ip} 'tail -f /var/log/instance-setup.log'"
}

output "instance_type" {
  description = "Current instance type"
  value       = var.instance_type
}

output "availability_zone" {
  description = "AZ the instance is deployed in"
  value       = aws_instance.main.availability_zone
}
