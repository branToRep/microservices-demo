output "vpc_id" {
  value = module.red.vpc_id
}

output "nombre_cluster" {
  description = "Para 'aws eks update-kubeconfig --name <esto>'."
  value       = module.cluster.nombre
}

output "endpoint_cluster" {
  value = module.cluster.endpoint
}

output "comando_kubeconfig" {
  description = "Copia y pega esto para hablar con el cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.cluster.nombre}"
}
