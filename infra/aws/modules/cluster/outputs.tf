output "nombre" {
  value = aws_eks_cluster.este.name
}

output "endpoint" {
  value = aws_eks_cluster.este.endpoint
}

output "grupo_seguridad_cluster" {
  description = "Util para abrirle puertos a RDS o a lo que haga falta despues."
  value       = aws_eks_cluster.este.vpc_config[0].cluster_security_group_id
}

output "asg_nodos" {
  description = "Grupo de autoescalado del node group, para registrar los nodos en el balanceador."
  value       = aws_eks_node_group.principal.resources[0].autoscaling_groups[0].name
}
