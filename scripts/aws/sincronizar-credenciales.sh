#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Sube las tres credenciales del laboratorio a donde las leen los workflows.
#
#   ./scripts/aws/sincronizar-credenciales.sh            -> a Vault (lo normal)
#   ./scripts/aws/sincronizar-credenciales.sh --github   -> a los secretos de GitHub
#
# Hay que correrlo al empezar CADA sesion del laboratorio: las credenciales
# caducan con ella, incluido aws_session_token.
#
# A VAULT: se guardan en boutique/aws. Los workflows las piden
# a Vault con un token de GitHub de diez minutos (OIDC), asi que GitHub no
# guarda ninguna credencial de AWS. Necesita Vault abierto y una sesion tuya:
#   ./scripts/vault/abrir.sh
#   vault login -method=userpass username=<tu-usuario>
#
# A GITHUB (--github): el camino de antes. Hace falta una sola vez, para el
# arranque: el workflow que instala Vault no puede sacar de Vault las
# credenciales con las que se construye Vault. Tambien sirve de respaldo si Vault
# esta sellado: los workflows lo usan solos cuando Vault no responde.
#
# Los valores nunca estan en este archivo: se leen de ~/.aws/credentials al
# ejecutarlo. Lo que se versiona es la receta.
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DESTINO=vault
[ "${1:-}" = "--github" ] && DESTINO=github

# Variables sueltas y no un array asociativo: el bash de macOS (3.2) no los tiene.
leer() {
  local valor
  valor=$(aws configure get "$1" || true)
  [ -n "$valor" ] || { echo "Falta $1 en ~/.aws/credentials" >&2; exit 1; }
  printf '%s' "$valor"
}
LLAVE=$(leer aws_access_key_id)
SECRETO=$(leer aws_secret_access_key)
SESION=$(leer aws_session_token)

if [ "$DESTINO" = github ]; then
  gh secret set AWS_ACCESS_KEY_ID --body "$LLAVE"
  gh secret set AWS_SECRET_ACCESS_KEY --body "$SECRETO"
  gh secret set AWS_SESSION_TOKEN --body "$SESION"
  echo "Listo: los tres secretos estan en GitHub."
  exit 0
fi

# shellcheck source=scripts/vault/entorno.sh
source scripts/vault/entorno.sh

[ "$(vault_estado sealed)" = "false" ] || {
  echo "Vault esta sellado. Abrelo con ./scripts/vault/abrir.sh (o usa --github)." >&2
  exit 1
}
vault token lookup >/dev/null 2>&1 || {
  echo "No tienes sesion en Vault. Haz:  vault login -method=userpass username=<tu-usuario>" >&2
  exit 1
}

vault kv put -mount=boutique aws \
  access_key_id="$LLAVE" \
  secret_access_key="$SECRETO" \
  session_token="$SESION" >/dev/null

echo "Listo: las tres credenciales estan en Vault (boutique/aws)."
echo "Version guardada: $(vault kv metadata get -mount=boutique -format=json aws | grep -o '"current_version": *[0-9]*' | grep -o '[0-9]*$')"
