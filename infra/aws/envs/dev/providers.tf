provider "aws" {
  region = var.region

  # Todo recurso nace etiquetado sin que nadie se acuerde. Es lo que permite
  # despues preguntarle a Cost Explorer cuanto costo ESTE proyecto.
  default_tags {
    tags = {
      Proyecto      = var.proyecto
      Entorno       = "dev"
      GestionadoPor = "terraform"
    }
  }
}
