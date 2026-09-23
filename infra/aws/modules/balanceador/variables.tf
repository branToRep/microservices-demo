variable "proyecto"          { type = string }
variable "vpc_id"            { type = string }
variable "subredes_publicas" { type = list(string) }

variable "asg_nodos" {
  description = "Grupo de autoescalado del node group de EKS. Los nodos se registran solos."
  type        = string
}

variable "nodeport_frontend" {
  description = "Puerto FIJO del Service frontend-external. Tiene que coincidir con el manifiesto."
  type        = number
  default     = 30080
}
