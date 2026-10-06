# Mismo bucket que el entorno dev, OTRA clave. Por eso se inicializa con el
# backend.hcl de dev, sin crear uno nuevo:
#
#   terraform init -backend-config=../dev/backend.hcl
#
# Que sea un estado aparte es lo que importa: apagar.sh destruye dev cada tarde
# y no puede ni ver este. Vault sobrevive a las sesiones del laboratorio.
terraform {
  backend "s3" {
    key          = "vault/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
