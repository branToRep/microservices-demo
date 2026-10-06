#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Crea (o actualiza) la cuenta de una persona en Vault.
#
#   ./scripts/vault/crear-usuario.sh <nombre> <admin|operador>
#
# Necesita un token con la politica admin (o el raiz, la primera vez). La
# contrasena se pide por teclado: no queda en el historial ni en la lista de
# procesos. La persona entra despues con:
#
#   vault login -method=userpass username=<nombre>
# -----------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/vault/entorno.sh
source "$(dirname "${BASH_SOURCE[0]}")/entorno.sh"

NOMBRE="${1:-}"
POLITICA="${2:-}"

case "$POLITICA" in
  admin|operador) ;;
  *) echo "Uso: $0 <nombre> <admin|operador>" >&2; exit 1 ;;
esac
[ -n "$NOMBRE" ] || { echo "Uso: $0 <nombre> <admin|operador>" >&2; exit 1; }

read -rsp "Contrasena para $NOMBRE: " CLAVE; echo
read -rsp "Repitela: " CLAVE2; echo
[ "$CLAVE" = "$CLAVE2" ] || { echo "No coinciden." >&2; exit 1; }
[ "${#CLAVE}" -ge 12 ] || { echo "Minimo 12 caracteres." >&2; exit 1; }

# password=- : la CLI lee ese valor de la entrada estandar.
printf '%s' "$CLAVE" | vault write "auth/userpass/users/$NOMBRE" \
  password=- \
  token_policies="$POLITICA" \
  token_ttl=8h \
  token_max_ttl=24h >/dev/null

echo "Cuenta '$NOMBRE' con la politica '$POLITICA'. Su sesion dura 8 h."
