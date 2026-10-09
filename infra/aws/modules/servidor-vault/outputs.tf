output "ip_publica" {
  value = aws_eip.vault.public_ip
}

output "id_instancia" {
  value = aws_instance.vault.id
}

output "vpc_id" {
  value = aws_vpc.vault.id
}
