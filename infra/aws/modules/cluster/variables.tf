variable "proyecto" { type = string }
variable "version_kubernetes" { type = string }
variable "tipo_instancia" { type = string }
variable "numero_nodos" { type = number }
variable "subredes_cluster" { type = list(string) }
variable "subredes_nodos" { type = list(string) }

variable "cidr_vpc" {
  description = "Rango de la VPC. Se usa para abrir el rango de NodePort al balanceador."
  type        = string
}
