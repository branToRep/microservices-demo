# operador — la persona que administra ESTA Vault (una por cuenta, ADR 0020).
#
# Es casi administrador, y no se disimula. Lo que gana frente al token raiz no es
# tener menos permisos, sino:
#   - sus tokens CADUCAN (1 h, renovables hasta 8 h); el raiz no caduca nunca;
#   - el registro de auditoria dice QUIEN fue, no "root";
#   - se revoca sin tocar nada mas, y el raiz deja de existir.
#
# Cubre exactamente lo que necesitan configurar-vault.yml (para poder repetirlo
# sin raiz) y los tickets siguientes (el metodo jwt del cluster).

# Secretos de la boutique: todo
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Politicas ACL
path "sys/policies/acl" {
  capabilities = ["list"]
}
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Metodos de autenticacion (userpass hoy; jwt del cluster despues)
path "sys/auth" {
  capabilities = ["read"]
}
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Motores de secretos
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Registro de auditoria (listarlo exige sudo)
path "sys/audit" {
  capabilities = ["read", "sudo"]
}
path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# Para que la UI sepa que mostrarle
path "sys/capabilities-self" {
  capabilities = ["update"]
}
