# -----------------------------------------------------------------------------
# operador: una persona del equipo en el dia a dia.
#
# Lee y escribe los secretos del proyecto (por ejemplo, subir las credenciales
# del laboratorio con scripts/aws/sincronizar-credenciales.sh). NO toca
# politicas, metodos de autenticacion ni la auditoria: eso es 'admin'.
# -----------------------------------------------------------------------------
path "boutique/data/*" {
  capabilities = ["create", "read", "update", "patch", "list"]
}

path "boutique/metadata/*" {
  capabilities = ["read", "list"]
}
