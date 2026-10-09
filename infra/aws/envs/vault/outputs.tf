output "ip_publica" {
  description = "La IP elastica. No cambia aunque el laboratorio detenga la maquina."
  value       = module.servidor_vault.ip_publica
}

output "vault_addr" {
  description = "Para 'export VAULT_ADDR=...' y para la VaultConnection del cluster."
  value       = "https://${module.servidor_vault.ip_publica}:8200"
}

output "id_instancia" {
  description = "Lo que SSM usa como destino. Ansible lo lee de aqui."
  value       = module.servidor_vault.id_instancia
}

output "comando_ssm" {
  description = "Abre una terminal en la maquina, sin puerto 22."
  value       = "aws ssm start-session --region ${var.region} --target ${module.servidor_vault.id_instancia}"
}
