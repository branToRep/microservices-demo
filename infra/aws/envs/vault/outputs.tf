output "vault_addr" {
  description = "Para 'export VAULT_ADDR=<esto>' y para la variable VAULT_ADDR del repositorio."
  value       = "https://${module.vault.ip_publica}:8200"
}

output "ip_publica" {
  value = module.vault.ip_publica
}

output "id_instancia" {
  description = "Para entrar sin SSH: aws ssm start-session --target <esto>"
  value       = module.vault.id_instancia
}

output "id_volumen_datos" {
  value = module.vault.id_volumen_datos
}

output "comando_sesion" {
  description = "Copia y pega esto para abrir una terminal en la maquina."
  value       = "aws ssm start-session --region ${var.region} --target ${module.vault.id_instancia}"
}
