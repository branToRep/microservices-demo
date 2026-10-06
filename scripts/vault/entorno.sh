# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Prepara la terminal para hablar con Vault. NO se ejecuta: se carga.
#
#   source scripts/vault/entorno.sh
#
# Lo cargan solos los demas scripts de esta carpeta. Deja puestas:
#
#   VAULT_ADDR    https://<ip-elastica>:8200. Si no esta puesta ya, la lee de la
#                 variable VAULT_ADDR del repositorio (gh) o del output de
#                 Terraform del entorno vault.
#   VAULT_CACERT  infra/vault/ca.pem, la CA propia del servidor. Sin ella la
#                 CLI rechaza el certificado, y es lo correcto.
#
# GIT BASH EN WINDOWS: vault.exe es un programa de Windows y Git Bash le
# "traduce" los argumentos que parecen rutas: file_path=/srv/vault/... llegaria
# como file_path=C:/Program Files/Git/srv/vault/... Por eso MSYS_NO_PATHCONV=1,
# y por eso la ruta de la CA se pasa ya en formato Windows con cygpath.
# -----------------------------------------------------------------------------

export MSYS_NO_PATHCONV=1

RAIZ="$(git rev-parse --show-toplevel)"

if ! command -v vault >/dev/null 2>&1; then
  cat >&2 <<'AYUDA'
Falta la CLI de Vault.
  Windows:  winget install Hashicorp.Vault     (o choco install vault)
  macOS:    brew install hashicorp/tap/vault
  Linux:    https://developer.hashicorp.com/vault/install
Despues abre una terminal nueva.
AYUDA
  return 1
fi

if [ -z "${VAULT_ADDR:-}" ] && command -v gh >/dev/null 2>&1; then
  VAULT_ADDR="$(gh variable get VAULT_ADDR 2>/dev/null || true)"
fi
if [ -z "${VAULT_ADDR:-}" ] && command -v terraform >/dev/null 2>&1; then
  VAULT_ADDR="$(terraform -chdir="$RAIZ/infra/aws/envs/vault" output -raw vault_addr 2>/dev/null || true)"
fi
if [ -z "${VAULT_ADDR:-}" ]; then
  echo "No se donde esta Vault. Haz:  export VAULT_ADDR=https://<ip-elastica>:8200" >&2
  return 1
fi
export VAULT_ADDR

VAULT_CACERT="$RAIZ/infra/vault/ca.pem"
if [ ! -f "$VAULT_CACERT" ]; then
  cat >&2 <<AYUDA
Falta $VAULT_CACERT

Es el certificado PUBLICO de la CA del servidor. Lo trae el workflow
"Servidor de Vault (Ansible)" como artefacto 'vault-ca'; se descarga y se
versiona en esa ruta (ver docs/VAULT.md, paso 3).
AYUDA
  return 1
fi
if command -v cygpath >/dev/null 2>&1; then
  VAULT_CACERT="$(cygpath -m "$VAULT_CACERT")"
fi
export VAULT_CACERT

# Lee un campo booleano de 'vault status -format=json' sin depender de jq, que
# Git Bash no trae.
vault_estado() {
  vault status -format=json 2>/dev/null |
    grep -o "\"$1\": *[a-z]*" | grep -o '[a-z]*$' || true
}
