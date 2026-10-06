# -----------------------------------------------------------------------------
# ci-lectura: lo que puede hacer un workflow de GitHub Actions.
#
# Solo LEER las credenciales de AWS. Ni escribir, ni listar, ni ver otros
# secretos. Si un workflow se viera comprometido, esto es todo lo que obtiene,
# y su token caduca en diez minutos.
#
# La asignan los roles 'ci' y 'despliegue' del metodo jwt (scripts/vault/configurar.sh).
# -----------------------------------------------------------------------------
path "boutique/data/aws" {
  capabilities = ["read"]
}
