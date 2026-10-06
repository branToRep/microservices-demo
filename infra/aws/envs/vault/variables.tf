variable "proyecto" {
  description = "Prefijo para el nombre de todos los recursos."
  type        = string
  default     = "boutique"
}

variable "region" {
  description = "El laboratorio solo permite us-east-1 y us-west-2."
  type        = string
  default     = "us-east-1"
}

variable "cidr_vpc" {
  description = "Rango de la red de Vault. Distinto del de dev a proposito."
  type        = string
  default     = "10.1.0.0/16"
}

variable "tipo_instancia" {
  type    = string
  default = "t3.small"
}

variable "tamano_disco_datos" {
  type    = number
  default = 10
}

variable "cidrs_api_vault" {
  description = <<-EOT
    Quien puede llegar al puerto 8200 (API y UI de Vault).
    0.0.0.0/0 a proposito: los runners de GitHub no tienen IP fija y el equipo
    trabaja desde redes distintas. La proteccion es TLS + autenticacion +
    politicas ACL, no la IP. Ver el ADR 0019.
    Para cerrarlo a redes concretas, pon aqui sus CIDR.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
