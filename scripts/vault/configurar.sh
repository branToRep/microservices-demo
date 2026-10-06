#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Configura Vault por dentro: auditoria, motor KV, politicas ACL y la entrada de
# GitHub Actions por OIDC.
#
#   VAULT_TOKEN=<token-raiz-o-admin> ./scripts/vault/configurar.sh
#
# Se puede correr las veces que haga falta: lo que ya existe no se toca, y las
# politicas y los roles se reescriben con lo que diga el repositorio. Es la
# forma de aplicar un cambio en infra/vault/politicas/.
#
# QUE DEJA:
#   auditoria   archivo en el disco de datos; cada peticion queda registrada
#   boutique/   motor KV v2 (con versiones) donde viven los secretos
#   politicas   las de infra/vault/politicas/*.hcl
#   github-actions/  metodo jwt: GitHub firma un token por ejecucion y Vault lo
#               acepta SOLO si viene de este repositorio. Dos roles:
#                 ci          cualquier rama de este repo  -> ci-lectura
#                 despliegue  solo main + entorno produccion -> ci-lectura
#   userpass/   usuario y contrasena para las personas (crear-usuario.sh)
# -----------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/vault/entorno.sh
source "$(dirname "${BASH_SOURCE[0]}")/entorno.sh"
cd "$RAIZ"   # las rutas de abajo son relativas: ver MSYS_NO_PATHCONV en entorno.sh

paso() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
alto() { printf '\n\033[1;31mALTO:\033[0m %s\n' "$*" >&2; exit 1; }

# owner/repo, sacado del remoto de git. Distingue mayusculas: GitHub firma
# "branToRep/microservices-demo" y eso es lo que Vault compara.
REPO="${REPO:-$(git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')}"
# La audiencia que pide el workflow (jwtGithubAudience en
# .github/actions/credenciales-aws). Tienen que coincidir.
AUDIENCIA="vault-boutique"
EMISOR="https://token.actions.githubusercontent.com"
DIR_AUDITORIA="/srv/vault/auditoria"

# --------------------------------------------------------------------------
paso "1/6  Comprobaciones"
echo "    Vault:       $VAULT_ADDR"
echo "    repositorio: $REPO"

[ "$(vault_estado sealed)" = "false" ] || alto "Vault esta sellado. Abrelo primero: ./scripts/vault/abrir.sh"
vault token lookup >/dev/null 2>&1 || alto "No hay token valido. Haz:  export VAULT_TOKEN=<token raiz o de admin>"

existe() { # existe <lista: auth|secrets|audit> <ruta/>
  vault "$1" list -format=json 2>/dev/null | grep -q "\"$2\""
}

# --------------------------------------------------------------------------
paso "2/6  Auditoria"
if existe audit "file/"; then
  echo "    ya activa"
else
  vault audit enable file file_path="$DIR_AUDITORIA/auditoria.log"
fi

# --------------------------------------------------------------------------
paso "3/6  Motor de secretos KV v2 en boutique/"
if existe secrets "boutique/"; then
  echo "    ya existe"
else
  vault secrets enable -path=boutique -version=2 \
    -description="Secretos del proyecto Boutique" kv
fi
# Guarda las diez ultimas versiones de cada secreto: se puede volver atras.
vault write boutique/config max_versions=10 >/dev/null

# --------------------------------------------------------------------------
paso "4/6  Politicas ACL"
for archivo in infra/vault/politicas/*.hcl; do
  nombre="$(basename "$archivo" .hcl)"
  vault policy write "$nombre" "$archivo" >/dev/null
  echo "    $nombre"
done

# --------------------------------------------------------------------------
paso "5/6  GitHub Actions por OIDC (metodo jwt en github-actions/)"
if existe auth "github-actions/"; then
  echo "    metodo ya activo"
else
  vault auth enable -path=github-actions \
    -description="Workflows de GitHub Actions, sin secretos guardados" jwt
fi

vault write auth/github-actions/config \
  oidc_discovery_url="$EMISOR" \
  bound_issuer="$EMISOR" >/dev/null

# Los tokens duran diez minutos: lo justo para un trabajo de CI. user_claim =
# actor hace que la auditoria diga QUE persona lanzo cada ejecucion.
#
# 'ci': cualquier rama de ESTE repositorio (los planes de Terraform de los PR y
# el workflow de Ansible). Un fork no puede: su token dice otro repository.
vault write auth/github-actions/role/ci - >/dev/null <<JSON
{
  "role_type": "jwt",
  "user_claim": "actor",
  "bound_audiences": ["$AUDIENCIA"],
  "bound_claims_type": "string",
  "bound_claims": { "repository": "$REPO" },
  "token_policies": ["ci-lectura"],
  "token_ttl": "10m",
  "token_max_ttl": "15m"
}
JSON
echo "    rol ci          -> $REPO, cualquier rama"

# 'despliegue': solo main Y solo desde el entorno 'produccion'. Si alguien
# anade "Required reviewers" a ese entorno, Vault no entrega nada hasta que se
# apruebe el despliegue.
vault write auth/github-actions/role/despliegue - >/dev/null <<JSON
{
  "role_type": "jwt",
  "user_claim": "actor",
  "bound_audiences": ["$AUDIENCIA"],
  "bound_claims_type": "string",
  "bound_claims": {
    "repository": "$REPO",
    "ref": "refs/heads/main",
    "environment": "produccion"
  },
  "token_policies": ["ci-lectura"],
  "token_ttl": "10m",
  "token_max_ttl": "15m"
}
JSON
echo "    rol despliegue  -> $REPO, main, entorno produccion"

# --------------------------------------------------------------------------
paso "6/6  Usuario y contrasena para las personas (userpass/)"
if existe auth "userpass/"; then
  echo "    ya activo"
else
  vault auth enable userpass
fi

cat <<FIN

Listo. Siguientes pasos:

  1. Una cuenta para ti y otra por persona del equipo:
       ./scripts/vault/crear-usuario.sh <nombre> admin
       ./scripts/vault/crear-usuario.sh <nombre> operador

  2. Las credenciales del laboratorio, a Vault:
       vault login -method=userpass username=<nombre>
       ./scripts/aws/sincronizar-credenciales.sh

  3. Cuando ya puedas entrar con tu usuario admin, revoca el token raiz:
       vault token revoke <token-raiz>
     Sacar otro exigira reunir tres partes de la llave (vault operator generate-root).
FIN
