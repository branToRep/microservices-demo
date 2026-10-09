provider "aws" {
  region = var.region

  # Entorno = "vault" y no "dev". No es cosmetico: apagar.sh busca la VPC del
  # cluster por etiquetas cuando ya no tiene el output de Terraform, y con la
  # misma etiqueta podria encontrar esta y barrer lo que no es suyo.
  default_tags {
    tags = {
      Proyecto      = var.proyecto
      Entorno       = "vault"
      GestionadoPor = "terraform"
    }
  }
}
