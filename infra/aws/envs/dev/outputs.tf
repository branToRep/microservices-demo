output "vpc_id" {
  value = module.red.vpc_id
}

output "subredes_publicas" {
  value = module.red.subredes_publicas
}

output "subredes_privadas" {
  value = module.red.subredes_privadas
}

output "nombre_cluster" {
  description = "Para 'aws eks update-kubeconfig --name <esto>'."
  value       = module.cluster.nombre
}

output "endpoint_cluster" {
  value = module.cluster.endpoint
}

output "grupo_seguridad_cluster" {
  description = "Util para abrirle puertos a RDS o a lo que haga falta despues."
  value       = module.cluster.grupo_seguridad_cluster
}

output "comando_kubeconfig" {
  description = "Copia y pega esto para hablar con el cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.cluster.nombre}"
}

output "url_tienda" {
  description = "Abre esto en el navegador."
  value       = "http://${module.balanceador.dns}"
}
