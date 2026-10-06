output "id_instancia" {
  description = "Para 'aws ssm start-session --target <esto>'."
  value       = aws_instance.vault.id
}

output "ip_publica" {
  value = aws_eip.vault.public_ip
}

output "id_volumen_datos" {
  value = aws_ebs_volume.datos.id
}

output "grupo_seguridad" {
  value = aws_security_group.vault.id
}
