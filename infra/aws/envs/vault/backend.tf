# El estado vive en el MISMO bucket que envs/dev, con otra clave.
#
# Otra clave y no otro bucket: el bucket ya existe, ya tiene versionado y es de
# cada operador. Lo que importa es que los dos estados no se pisen, y eso lo da
# la clave. Con estados separados, 'terraform destroy' en envs/dev (lo que hace
# apagar.sh cada sesion) no sabe siquiera que esta maquina existe.
#
# No hay backend.hcl propio: se reutiliza el de envs/dev, que ya dice que bucket
# es el tuyo. Un solo sitio donde cambiarlo.
#
#   terraform init -backend-config=../dev/backend.hcl
terraform {
  backend "s3" {
    key          = "vault/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
