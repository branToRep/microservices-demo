# El estado vive en el bucket que creo infra/aws/bootstrap/crear-bucket-estado.sh.
# use_lockfile hace el bloqueo con S3 a secas: desde Terraform 1.10 no hace falta
# la tabla de DynamoDB que ensenan los tutoriales viejos.
terraform {
  backend "s3" {
    bucket       = "boutique-tfstate-devops"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
