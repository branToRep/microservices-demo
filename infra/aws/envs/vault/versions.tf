terraform {
  # Las mismas restricciones que envs/dev, y por las mismas razones (ver
  # docs/infra.md): use_lockfile necesita 1.10, y el tope evita Terraform 2.x.
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
