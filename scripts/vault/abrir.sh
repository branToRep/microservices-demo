#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Abre (unseal) Vault con las partes de la llave de Shamir.
#
#   ./scripts/vault/abrir.sh
#
# Hace falta despues de CADA arranque de la maquina: al cerrar la sesion del
# laboratorio la instancia se detiene, y Vault arranca siempre sellado. Sellado,
# no entrega ningun secreto y el despliegue cae al respaldo de los secretos de
# GitHub (o se salta).
#
# Pide UNA parte. El progreso lo guarda el servidor, no tu PC: tres personas
# pueden meter una parte cada una desde tres PCs distintos. Si tu tienes varias,
# corre el script otra vez.
#
# La parte se escribe sin que se vea y no queda en el historial.
# -----------------------------------------------------------------------------
set -euo pipefail
# shellcheck source=scripts/vault/entorno.sh
source "$(dirname "${BASH_SOURCE[0]}")/entorno.sh"

echo "Vault: $VAULT_ADDR"

case "$(vault_estado sealed)" in
  false) echo "Vault ya esta abierto."; exit 0 ;;
  true)  ;;
  *)     echo "No consigo hablar con Vault en $VAULT_ADDR. Esta la maquina encendida?" >&2; exit 1 ;;
esac

# Sin argumento, la CLI pide la parte por teclado y no la muestra. Sale con
# codigo 2 mientras siga sellado, que aqui no es un error.
vault operator unseal || true

if [ "$(vault_estado sealed)" = "false" ]; then
  echo "Abierto. Vault ya entrega secretos."
else
  echo "Parte aceptada. Faltan mas: que otra persona (o tu) corra este script."
fi
