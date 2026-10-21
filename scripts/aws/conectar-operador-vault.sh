#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Instala el Vault Secrets Operator en el cluster y lo apunta a TU Vault
# (ADR 0020).
#
#   bash scripts/aws/conectar-operador-vault.sh
#
# Lo llama levantar.sh despues de avisar-a-vault.sh y antes de la tienda, pero
# se puede correr solo, con el cluster ya levantado. Repetirlo no cambia nada.
#
# Lo que pone, y por que aqui y no en el chart:
#   1. el operador, como release de Helm aparte y con version fija. Es
#      plataforma, con sus propios CRD; dentro de la release de la tienda daria
#      problemas al actualizar (ADR 0020).
#   2. la CA de tu Vault, en el Secret vault-ca. Es un certificado PUBLICO: no
#      hay nada que proteger, solo con que verificar.
#   3. la VaultConnection 'vault': la direccion y esa CA. Cambian de un operador
#      a otro, asi que no pueden ir en el chart que despliega el pipeline.
#
# Lo que NO pone: ni tokens ni el secreto. El operador entra solo, con la
# ServiceAccount lector-vault que crea el chart.
# -----------------------------------------------------------------------------
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$RAIZ/infra/aws/envs/dev/backend.hcl"

# La version del operador, FIJA, como la de Kubernetes y la de Vault. La 1.6.0
# se probo contra Kubernetes 1.34.11, la misma version que corren los nodos.
VERSION_OPERADOR=1.6.0
NS_OPERADOR=vault-secrets-operator-system
NS_TIENDA=default
CONEXION=vault
SECRETO_CA=vault-ca

paso() { printf '    %s\n' "$*"; }
alto() { printf '\n\033[1;31mALTO:\033[0m %s\n' "$*" >&2; exit 1; }

for herramienta in kubectl helm terraform; do
  command -v "$herramienta" >/dev/null || alto "Falta '$herramienta'. Ver scripts/aws/levantar.sh (paso 1)."
done

# Igual que avisar-a-vault.sh: la direccion sale del estado de envs/vault, en el
# mismo bucket que el cluster, asi que siempre es la Vault de ESTA cuenta.
if [ -z "${VAULT_ADDR:-}" ]; then
  terraform -chdir="$RAIZ/infra/aws/envs/vault" init -input=false -reconfigure \
    -backend-config="$BACKEND" >/dev/null
  VAULT_ADDR=$(terraform -chdir="$RAIZ/infra/aws/envs/vault" output -raw vault_addr 2>/dev/null) \
    || alto "No hay Vault en esta cuenta. Levantala con:  bash scripts/aws/levantar-vault.sh"
fi
VAULT_CACERT="${VAULT_CACERT:-$HOME/.vault-boutique/ca.crt}"
[ -f "$VAULT_CACERT" ] || alto "Falta la CA de Vault en $VAULT_CACERT.
       La deja levantar-vault.sh:  bash scripts/aws/levantar-vault.sh"

# ----------------------------------------------------------- 1. el operador
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp >/dev/null
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --version "$VERSION_OPERADOR" \
  --namespace "$NS_OPERADOR" --create-namespace \
  --wait --timeout 5m >/dev/null \
  || alto "El operador no arranco. Mira:  kubectl -n $NS_OPERADOR get pods"
paso "Operador $VERSION_OPERADOR en $NS_OPERADOR"

# ----------------------------------------------------------- 2. la CA
# El operador la busca bajo la clave ca.crt. create --dry-run | apply: asi se
# puede repetir, y si la CA cambio (Vault recreada), se actualiza.
kubectl -n "$NS_TIENDA" create secret generic "$SECRETO_CA" \
  --from-file=ca.crt="$VAULT_CACERT" --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null

# ----------------------------------------------------------- 3. la conexion
# Verificando TLS con esa CA, nunca skipTLSVerify.
kubectl apply -f - >/dev/null <<CONEXION
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: $CONEXION
  namespace: $NS_TIENDA
spec:
  address: $VAULT_ADDR
  caCertSecretRef: $SECRETO_CA
CONEXION
paso "VaultConnection '$CONEXION' -> $VAULT_ADDR (TLS con la CA de tu Vault)"
