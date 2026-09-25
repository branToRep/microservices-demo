#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Levanta todo: infraestructura en AWS + la tienda en Kubernetes.
#
#   ./scripts/aws/levantar.sh
#
# Lo unico que hay que hacer antes es pegar las credenciales del laboratorio en
# ~/.aws/credentials (Start Lab -> AWS Details -> AWS CLI). El resto lo hace el
# script, incluidas las dos comprobaciones que mas tiempo han costado:
#
#   - que las credenciales sirvan de verdad (sts get-caller-identity NO sirve
#     de prueba: responde igual con credenciales canceladas por la SCP)
#   - que kubectl apunte al cluster de AWS y no al de Docker Desktop
#
# Tarda entre 12 y 18 minutos, casi todo esperando a que EKS cree el plano de
# control. Se puede volver a correr sin miedo: Terraform solo crea lo que falta.
# -----------------------------------------------------------------------------
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTORNO="$RAIZ/infra/aws/envs/dev"

paso() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
alto() { printf '\n\033[1;31mALTO:\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
paso "1/7  Comprobando la configuracion del backend"

if [ ! -f "$ENTORNO/backend.hcl" ]; then
  cat >&2 <<AYUDA

No existe $ENTORNO/backend.hcl

Es el archivo con el nombre de TU bucket de estado, y no se versiona porque
cambia de una maquina a otra. Crealo asi:

  cd infra/aws/envs/dev
  cp backend.hcl.ejemplo backend.hcl
  \$EDITOR backend.hcl          # pon un nombre unico en todo AWS

Si el bucket no existe todavia, creralo una sola vez con:

  ./infra/aws/bootstrap/crear-bucket-estado.sh <ese-mismo-nombre>

AYUDA
  exit 1
fi

# Una clave declarada dos veces daba antes un valor con salto de linea dentro,
# y de ahi salian rutas como "s3://bucket\nbucket/". Se cuenta primero.
leer_clave() {
  local clave="$1" archivo="$2" n
  n=$(grep -cE "^[[:space:]]*${clave}[[:space:]]*=" "$archivo" || true)
  if [ "$n" -gt 1 ]; then
    alto "backend.hcl declara '${clave}' $n veces. Deja una sola linea.
       Miralo con:  grep -n '${clave}' $archivo"
  fi
  sed -nE "s/^[[:space:]]*${clave}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" "$archivo" | head -1
}

BUCKET=$(leer_clave bucket "$ENTORNO/backend.hcl")
REGION=$(leer_clave region "$ENTORNO/backend.hcl")
REGION="${REGION:-us-east-1}"

[ -n "$BUCKET" ] || alto "backend.hcl no declara ningun bucket."
[ "$BUCKET" = "boutique-tfstate-CAMBIAME" ] && \
  alto "backend.hcl sigue con el valor de la plantilla. Pon tu nombre de bucket."

echo "    bucket: $BUCKET"
echo "    region: $REGION"

# --------------------------------------------------------------------------
paso "2/7  Comprobando que las credenciales sirvan"

if ! aws s3 ls "s3://$BUCKET/" >/dev/null 2>&1; then
  cat >&2 <<AYUDA

No puedo leer s3://$BUCKET/

Casi siempre es una de dos cosas:

  a) La sesion del laboratorio termino. Dale a Start Lab y vuelve a pegar las
     TRES lineas en ~/.aws/credentials (incluido aws_session_token, que cambia
     cada vez).

  b) El bucket no existe todavia:
     ./infra/aws/bootstrap/crear-bucket-estado.sh $BUCKET

AYUDA
  exit 1
fi
echo "    ok"

# --------------------------------------------------------------------------
paso "3/7  Preparando Terraform"
cd "$ENTORNO"
terraform init -input=false -backend-config=backend.hcl

# --------------------------------------------------------------------------
paso "4/7  Creando la infraestructura (esto es lo que tarda)"
terraform apply -auto-approve

CLUSTER=$(terraform output -raw nombre_cluster)
URL=$(terraform output -raw url_tienda)

# --------------------------------------------------------------------------
paso "5/7  Apuntando kubectl al cluster de AWS"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null

CONTEXTO="$(kubectl config current-context)"
case "$CONTEXTO" in
  *":cluster/$CLUSTER") echo "    ok: $CONTEXTO" ;;
  *) alto "kubectl apunta a '$CONTEXTO', no al cluster de AWS.
       Once pods corriendo en el Kubernetes de tu Mac parecen exito y no lo son." ;;
esac

# --------------------------------------------------------------------------
paso "6/7  Desplegando la tienda"
cd "$RAIZ"
kubectl apply -k kubernetes-manifests/

echo "    esperando a que los despliegues esten disponibles..."
kubectl wait --for=condition=available --timeout=420s deployment --all || {
  echo
  echo "Algun despliegue no arranco. Mira cual:"
  echo "  kubectl get pods"
  echo "  kubectl describe pod <el-que-falle>"
  exit 1
}

# --------------------------------------------------------------------------
paso "7/7  Esperando al balanceador"
# Los pods pueden estar listos y el ELB seguir marcando los nodos OutOfService:
# sus comprobaciones de salud tardan hasta un minuto en dar el visto bueno.
for _ in $(seq 1 40); do
  CODIGO=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL" || true)
  [ "$CODIGO" = "200" ] && break
  printf '.'
  sleep 10
done
echo

if [ "${CODIGO:-000}" != "200" ]; then
  cat >&2 <<AYUDA

La tienda no responde 200 todavia ($URL devuelve $CODIGO).

Lo mas comun es que el nodePort del Service y el del balanceador no coincidan.
Tienen que ser el mismo numero en los dos sitios:

  kubectl get svc frontend-external -o jsonpath='{.spec.ports[0].nodePort}{"\n"}'
  grep nodeport_frontend infra/aws/envs/dev/variables.tf

AYUDA
  exit 1
fi

printf '\n\033[1;32mListo.\033[0m  %s\n\n' "$URL"
echo "Para apagar cuando termines:  ./scripts/aws/apagar.sh"
