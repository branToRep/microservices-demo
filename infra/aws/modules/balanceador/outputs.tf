output "dns" {
  description = "La URL publica de la tienda."
  value       = aws_elb.frontend.dns_name
}

output "nombre" {
  value = aws_elb.frontend.name
}
