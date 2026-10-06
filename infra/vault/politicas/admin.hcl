# -----------------------------------------------------------------------------
# admin: quien administra Vault.
#
# Existe para poder REVOCAR el token raiz despues de configurar. Con el raiz
# revocado, sacar uno nuevo exige reunir otra vez tres partes de la llave de
# Shamir ('vault operator generate-root'): nadie tiene poder total en solitario.
#
# Puede gestionar politicas, metodos de autenticacion, motores de secretos y la
# auditoria, y todos los secretos del proyecto. NO puede desactivar el sellado
# por Shamir ni regenerar las llaves: eso sigue exigiendo el umbral de partes.
# -----------------------------------------------------------------------------

# Politicas ACL
path "sys/policies/acl" {
  capabilities = ["list"]
}
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Metodos de autenticacion (jwt de GitHub, userpass) y tokens; incluye
# auth/token/*, que permite revocar el token raiz cuando ya no hace falta.
path "sys/auth" {
  capabilities = ["read"]
}
path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Motores de secretos
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Los secretos del proyecto
path "boutique/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}

# Auditoria
path "sys/audit" {
  capabilities = ["read", "sudo"]
}
path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# Salud, y sellar en una emergencia (abrir sigue necesitando las partes)
path "sys/health" {
  capabilities = ["read", "sudo"]
}
path "sys/seal" {
  capabilities = ["update", "sudo"]
}

# Copias de seguridad del almacenamiento Raft
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
