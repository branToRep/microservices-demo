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
  description = <<-EOT
    Version de Kubernetes del plano de control.

    FIJADA A PROPOSITO. Con null, EKS elige "la mas reciente de hoy", asi que la
    misma etiqueta de Git daria un cluster distinto en seis meses. Eso rompe la
    promesa del versionado.

    1.34 y no 1.36: la version mas nueva tarda en tener todos los addons
    estables, y la mas vieja se acerca al fin de soporte. Dos por detras de la
    punta es el punto comodo.

    Versiones que admite el laboratorio: 1.31 a 1.36.
  EOT
  type        = string
  default     = "1.34"
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

variable "nodeport_frontend" {
  description = <<-EOT
    Puerto fijo del Service frontend-external.

    TIENE que coincidir con el nodePort declarado en
    kubernetes-manifests/frontend.yaml. Si uno de los dos cambia, el balanceador
    comprueba un puerto donde no escucha nadie y los nodos salen OutOfService.
  EOT
  type        = number
  default     = 30080
}
