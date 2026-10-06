#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Inicializa Vault: genera la llave maestra partida en CINCO partes con el
# algoritmo de Shamir, de las que hacen falta TRES para abrirlo, y el token raiz.
#
#   ./scripts/vault/inicializar.sh
#
# Se corre UNA SOLA VEZ en la vida del servidor, desde el PC de una persona y
# nunca desde GitHub Actions: las partes de la llave no pueden acabar en un log.
#
# Despues de correrlo:
#   1. Reparte las cinco partes entre cinco personas (o las que haya; nadie
#      deberia tener tres). Cada quien la guarda en su gestor de contrasenas.
#   2. Abre Vault con tres partes:        ./scripts/vault/abrir.sh
#   3. Configuralo con el token raiz:     ./scripts/vault/configurar.sh
#   4. BORRA el archivo que deja este script.
# -----------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/vault/entorno.sh
source "$(dirname "${BASH_SOURCE[0]}")/entorno.sh"

PARTES=5
UMBRAL=3

echo "Vault: $VAULT_ADDR"

case "$(vault_estado initialized)" in
  true)  echo "Vault YA esta inicializado. No hay nada que hacer aqui."; exit 0 ;;
  false) ;;
  *)     echo "No consigo hablar con Vault en $VAULT_ADDR. Esta la maquina encendida?" >&2; exit 1 ;;
esac

# Fuera del repositorio, para que no haya forma de versionarlo por accidente.
SALIDA="$HOME/vault-init-$(date +%Y%m%d-%H%M%S).json"
umask 077

vault operator init \
  -key-shares="$PARTES" \
  -key-threshold="$UMBRAL" \
  -format=json > "$SALIDA"

cat <<FIN

Vault inicializado: $PARTES partes, hacen falta $UMBRAL para abrirlo.

Las partes y el token raiz estan en:
  $SALIDA

  - unseal_keys_b64[0..4]  las cinco partes. Una por persona.
  - root_token             el token raiz. Solo para configurar.sh; despues se
                           revoca.

Vault sigue SELLADO. Siguientes pasos:
  ./scripts/vault/abrir.sh
  VAULT_TOKEN=<root_token> ./scripts/vault/configurar.sh

Y cuando cada quien tenga su parte guardada, BORRA el archivo:
  rm "$SALIDA"
FIN
