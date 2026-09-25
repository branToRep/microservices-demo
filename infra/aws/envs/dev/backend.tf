# El estado vive en S3, en un bucket que NO se nombra aqui.
#
# POR QUE: los nombres de bucket son unicos en todo AWS. Escribir el nuestro a
# fuego obligaba a cualquier otra persona a editar codigo antes de poder correr
# el proyecto, que es justo lo contrario de reproducible. Con configuracion
# parcial, lo que cambia de una maquina a otra se pasa en el init:
#
#   cp backend.hcl.ejemplo backend.hcl     # y edita el nombre del bucket
#   terraform init -backend-config=backend.hcl
#
# Lo que queda abajo es igual para todo el mundo y por eso si va versionado.
# use_lockfile hace el bloqueo con S3 a secas: desde Terraform 1.10 no hace
# falta la tabla de DynamoDB que ensenan los tutoriales viejos.
terraform {
  backend "s3" {
    key          = "dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
