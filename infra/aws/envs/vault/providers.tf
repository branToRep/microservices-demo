provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Proyecto      = var.proyecto
      Entorno       = "vault"
      GestionadoPor = "terraform"
    }
  }
}
