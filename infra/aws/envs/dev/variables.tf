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
  description = "Rango de la red."
  type        = string
  default     = "10.0.0.0/16"
}

variable "crear_nat" {
  description = <<-EOT
    Decision del ticket #39.

    false = los nodos van en subredes publicas con IP publica. Ahorra ~33 USD/mes
            mas 0,045 USD/GB. Menos seguro: NO es lo que se haria en produccion,
            pero el entorno se destruye cada sesion.
    true  = un solo NAT Gateway y los nodos en subredes privadas.
  EOT
  type        = bool
  default     = false
}

variable "version_kubernetes" {
  description = "Version de Kubernetes. null = la que EKS elija por defecto."
  type        = string
  default     = null
}

variable "tipo_instancia" {
  description = "El laboratorio solo permite hasta 'large'."
  type        = string
  default     = "t3.medium"
}

variable "numero_nodos" {
  description = "Nodos deseados. Poner a 0 para apagar sin destruir."
  type        = number
  default     = 2
}
