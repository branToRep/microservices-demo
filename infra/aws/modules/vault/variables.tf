variable "proyecto" { type = string }
variable "vpc_id" { type = string }

variable "subred" {
  description = "Subred PUBLICA donde vive la instancia (necesita salida a internet para SSM)."
  type        = string
}

variable "tipo_instancia" {
  description = "t3.small sobra para un Vault de un solo nodo."
  type        = string
  default     = "t3.small"
}

variable "tamano_disco_datos" {
  description = "GB del disco donde viven los datos de Vault."
  type        = number
  default     = 10
}

variable "cidrs_api_vault" {
  description = "Quien puede llegar al 8200. Ver la variable del entorno."
  type        = list(string)
}

variable "perfil_instancia" {
  description = "Perfil de instancia que ya trae la cuenta del laboratorio."
  type        = string
  default     = "LabInstanceProfile"
}
