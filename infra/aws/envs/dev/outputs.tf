output "vpc_id" {
  value = module.red.vpc_id
}

output "subredes_publicas" {
  value = module.red.subredes_publicas
}

output "subredes_privadas" {
  value = module.red.subredes_privadas
}

# Llegan con el ticket #40, junto con el modulo cluster.
#
# output "nombre_cluster" {
#   description = "Para 'aws eks update-kubeconfig --name <esto>'."
#   value       = module.cluster.nombre
# }
#
# output "comando_kubeconfig" {
#   value = "aws eks update-kubeconfig --region ${var.region} --name ${module.cluster.nombre}"
# }
