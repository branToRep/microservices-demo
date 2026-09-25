#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Sube las tres credenciales del laboratorio a los secretos del repositorio.
#
#   ./scripts/aws/sincronizar-credenciales.sh
#
# Hay que correrlo al empezar CADA sesion del laboratorio: las credenciales
# caducan con ella, incluido aws_session_token, y los secretos de GitHub son una
# foto, no una conexion. Sin esto, el trabajo "desplegar" del pipeline se salta
# con un aviso y el trabajo "plan" de terraform-ci tambien.
#
# Los valores nunca estan en este archivo: se leen de ~/.aws/credentials al
# ejecutarlo. Lo que se versiona es la receta.
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

for v in aws_access_key_id aws_secret_access_key aws_session_token; do
  val=$(aws configure get "$v")
  [ -z "$val" ] && { echo "Falta $v en ~/.aws/credentials"; exit 1; }
  gh secret set "$(echo "$v" | tr '[:lower:]' '[:upper:]')" --body "$val"
done
echo "Listo: los tres secretos estan en GitHub."
