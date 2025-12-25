output "instance_id" {
  description = "ID of the bastion EC2 instance"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "private_ip" {
  description = "Private IP address of the bastion host"
  value       = aws_instance.bastion.private_ip
}

output "security_group_id" {
  description = "Security group ID of the bastion host"
  value       = aws_security_group.bastion.id
}

output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.bastion.key_name
}

output "private_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the SSH private key"
  value       = aws_secretsmanager_secret.bastion_key.arn
}

output "ssh_command" {
  description = "Command to SSH to the bastion"
  value       = "ssh -i ${var.name}-bastion.pem ec2-user@${aws_instance.bastion.public_ip}"
}

output "get_key_command" {
  description = "Command to retrieve the SSH private key from Secrets Manager"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.bastion_key.arn} --query SecretString --output text > ${var.name}-bastion.pem && chmod 600 ${var.name}-bastion.pem"
}

output "ssm_command" {
  description = "Command to connect via SSM"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id}"
}
