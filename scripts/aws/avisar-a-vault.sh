#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Le dice a Vault en que cluster confiar EN ESTA SESION (ADR 0020).
#
#   bash scripts/aws/avisar-a-vault.sh
#
# Lo llama levantar.sh antes de desplegar la tienda, pero se puede correr solo,
# con el cluster ya levantado.
#
# Por que hace falta en cada sesion: Vault valida los tokens del cluster con las
# llaves publicas de su emisor OIDC, y ese emisor es distinto cada vez que el
# cluster se crea. Con el emisor de ayer, Vault rechaza a todo el mundo.
#
# Lo que hace, y nada mas:
#   1. comprueba que Vault responda; si esta sellada, pide 2 llaves por teclado
#   2. comprueba que haya una sesion tuya; si no, te pide entrar con tu usuario
#   3. escribe el emisor del cluster de hoy en auth/eks/config
#
# NO crea el metodo ni el rol: eso es configuracion permanente y la pone Ansible
# (configurar-vault.yml). Este script solo escribe lo que cambia.
#
# El token de tu sesion lo guarda 'vault login' en ~/.vault-token y caduca en una
# hora. Nada de lo que hace este script pasa por GitHub.
# -----------------------------------------------------------------------------
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$RAIZ/infra/aws/envs/dev/backend.hcl"
REGION="${REGION:-us-east-1}"
CLUSTER="${CLUSTER:-boutique}"
RUTA_JWT=eks
ROL_JWT=boutique

paso() { printf '    %s\n' "$*"; }
alto() { printf '\n\033[1;31mALTO:\033[0m %s\n' "$*" >&2; exit 1; }

for herramienta in vault jq aws terraform; do
  command -v "$herramienta" >/dev/null || alto "Falta '$herramienta'. Ver ansible/README.md (Requisitos)."
done

# --------------------------------------------------------------- donde esta
# La direccion sale del estado de envs/vault, en el mismo bucket que el cluster:
# siempre la Vault de ESTA cuenta.
if [ -z "${VAULT_ADDR:-}" ]; then
  terraform -chdir="$RAIZ/infra/aws/envs/vault" init -input=false -reconfigure \
    -backend-config="$BACKEND" >/dev/null
  VAULT_ADDR=$(terraform -chdir="$RAIZ/infra/aws/envs/vault" output -raw vault_addr 2>/dev/null) \
    || alto "No hay Vault en esta cuenta (envs/vault no tiene estado). Levantala con:
       bash scripts/aws/levantar-vault.sh"
fi
export VAULT_ADDR
export VAULT_CACERT="${VAULT_CACERT:-$HOME/.vault-boutique/ca.crt}"
[ -f "$VAULT_CACERT" ] || alto "Falta la CA de Vault en $VAULT_CACERT.
       La deja levantar-vault.sh:  bash scripts/aws/levantar-vault.sh"

# --------------------------------------------------------------- 1. el sello
ESTADO=$(vault status -format=json 2>/dev/null || true)
[ -n "$ESTADO" ] || alto "Vault no responde en $VAULT_ADDR.
       Si el laboratorio detuvo la maquina:  bash scripts/aws/levantar-vault.sh"
[ "$(jq -r .initialized <<<"$ESTADO")" = "true" ] || alto "Vault no esta inicializada.
       Ver docs/OPERACION-VAULT.md, secciones 1 a 5."

if [ "$(jq -r .sealed <<<"$ESTADO")" = "true" ]; then
  paso "Vault esta sellada (la maquina se reinicio). Hacen falta 2 de tus 3 llaves."
  # Por teclado, sin argumento: asi la llave no queda en el historial.
  for _ in 1 2 3; do
    vault operator unseal >/dev/null || true
    [ "$(vault status -format=json 2>/dev/null | jq -r .sealed)" = "false" ] && break
  done
  [ "$(vault status -format=json 2>/dev/null | jq -r .sealed)" = "false" ] \
    || alto "Vault sigue sellada. Vuelve a correr este script con dos llaves distintas."
fi
paso "Vault desellada en $VAULT_ADDR"

# --------------------------------------------------------------- 2. quien eres
# Un VAULT_TOKEN viejo en el entorno (el raiz revocado, uno caducado) gana a
# ~/.vault-token: se descarta aqui, solo dentro de este script.
if ! vault token lookup >/dev/null 2>&1; then
  unset VAULT_TOKEN
fi
if ! vault token lookup >/dev/null 2>&1; then
  USUARIO="${VAULT_USUARIO:-}"
  [ -n "$USUARIO" ] || read -rp "    Tu usuario de Vault: " USUARIO
  # -no-print: sin el, 'vault login' imprime el token en la terminal.
  vault login -no-print -method=userpass username="$USUARIO" \
    || alto "No pude entrar como '$USUARIO'. Ver docs/OPERACION-VAULT.md, seccion 5."
fi
paso "Sesion de $(vault token lookup -format=json | jq -r .data.display_name)"

# --------------------------------------------------------------- 3. el emisor
vault read "auth/$RUTA_JWT/role/$ROL_JWT" >/dev/null 2>&1 || alto "Vault no tiene el metodo auth/$RUTA_JWT/ o el rol $ROL_JWT.
       Es configuracion permanente; ponla una vez con tu usuario:
         cd ansible && export ANSIBLE_CONFIG=\$PWD/ansible.cfg && ansible-playbook configurar-vault.yml"

EMISOR=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query cluster.identity.oidc.issuer --output text 2>/dev/null) \
  || alto "No encuentro el cluster '$CLUSTER' en $REGION. Levantalo primero."

# Al escribirlo, Vault descarga el documento de descubrimiento del emisor y sus
# llaves. Si no pudiera llegar a ellas, falla AQUI, con el motivo, y no cuando el
# cluster intente entrar.
vault write "auth/$RUTA_JWT/config" \
  oidc_discovery_url="$EMISOR" \
  bound_issuer="$EMISOR" >/dev/null \
  || alto "Vault no acepto el emisor $EMISOR (mira el mensaje de arriba)."
paso "Vault confia en el cluster de hoy: $EMISOR"
