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
  description = <<-EOF2
    Rango de la red de Vault.

    Distinto del de envs/dev (10.0.0.0/16) aunque las dos VPC no se conectan:
    es para que nadie confunda una con otra en la consola. Si algun dia se
    emparejaran, ademas, dos rangos iguales lo harian imposible.
  EOF2
  type        = string
  default     = "10.1.0.0/16"
}

variable "tipo_instancia" {
  description = "Vault con un secreto no necesita mas. El laboratorio permite hasta 'large'."
  type        = string
  default     = "t3.micro"
}

variable "perfil_instancia" {
  description = <<-EOF2
    Perfil de instancia que ya trae la cuenta del laboratorio. Es el que da
    permiso de SSM a la maquina. Se REFERENCIA, no se crea: el laboratorio no
    deja crear roles (ADR 0015). Medido en el ADR 0020.
  EOF2
  type        = string
  default     = "LabInstanceProfile"
}

variable "ruta_llave_publica" {
  description = <<-EOF2
    Llave publica para el SSH que viaja DENTRO del tunel SSM (ADR 0020).

    Cada operador genera la suya una vez, fuera del repositorio:
      ssh-keygen -t ed25519 -f ~/.ssh/boutique-vault -C "boutique-vault"

    Solo se lee la .pub. La privada nunca sale de ~/.ssh.
  EOF2
  type        = string
  default     = "~/.ssh/boutique-vault.pub"
}

variable "disco_gb" {
  description = "Disco raiz. Vault guarda ahi sus datos (almacenamiento en archivo)."
  type        = number
  default     = 10
}
