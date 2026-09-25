terraform {
  # "~> 1.10" significa: de 1.10 en adelante, pero por debajo de 2.0.
  #
  # El limite inferior no es capricho: use_lockfile en el backend de S3 (el
  # bloqueo del estado sin DynamoDB) aparecio en 1.10, y con 1.9 backend.tf no
  # funciona. El superior evita que dentro de dos anios alguien corra Terraform
  # 2.x y obtenga algo que no se parece a lo que dice la etiqueta.
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
