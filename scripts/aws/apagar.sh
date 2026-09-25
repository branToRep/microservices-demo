#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Apaga todo y destruye la infraestructura, en el orden que no deja residuos.
#
#   ./scripts/aws/apagar.sh
#
# EL ORDEN NO ES NEGOCIABLE, y es lo unico que este script aporta sobre un
# "terraform destroy" a secas.
#
# Terraform destruye lo que Terraform creo, y nada mas. Kubernetes y EKS crean
# cosas por su cuenta dentro de la VPC, y si los nodos mueren con los pods
# encima, esas cosas se quedan colgadas bloqueando el borrado de las subredes
# con DependencyViolation. Terraform reintenta veinte minutos y se rinde, y el
# error nunca menciona la causa.
#
# Son tres residuos, y cada uno tiene un dueno distinto:
#
#   k8s-elb-...           el controlador de Kubernetes, para un Service
#                         de tipo LoadBalancer. Sobrevive al ELB.
#   aws-K8S-i-...         el CNI, interfaces extra para dar IPs a los pods.
#                         Se quedan en "available" si el nodo muere con
#                         pods encima.
#   eks-cluster-sg-...    EKS mismo, al crear el cluster. Deberia irse con
#                         el cluster; a veces se rezaga.
#
# Quitar los pods PRIMERO es lo que evita casi todo: si se van antes que los
# nodos, el CNI devuelve sus interfaces solo. El barrido de mas abajo es la red
# de seguridad para cuando algo se rezaga igual.
# -----------------------------------------------------------------------------
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTORNO="$RAIZ/infra/aws/envs/dev"

paso() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
alto() { printf '\n\033[1;31mALTO:\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
paso "1/5  Comprobaciones"

[ -f "$ENTORNO/backend.hcl" ] || alto "No existe $ENTORNO/backend.hcl. Corre primero levantar.sh."

# Igual que en levantar.sh: una clave repetida metia un salto de linea en el valor.
leer_clave() {
  local clave="$1" archivo="$2" n
  n=$(grep -cE "^[[:space:]]*${clave}[[:space:]]*=" "$archivo" || true)
  [ "$n" -gt 1 ] && alto "backend.hcl declara '${clave}' $n veces. Deja una sola linea."
  sed -nE "s/^[[:space:]]*${clave}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" "$archivo" | head -1
}

BUCKET=$(leer_clave bucket "$ENTORNO/backend.hcl")
REGION=$(leer_clave region "$ENTORNO/backend.hcl")
REGION="${REGION:-us-east-1}"

aws s3 ls "s3://$BUCKET/" >/dev/null 2>&1 || alto "No puedo leer s3://$BUCKET/.
       La sesion del laboratorio termino. Start Lab y vuelve a pegar las
       credenciales en ~/.aws/credentials (incluido aws_session_token)."
echo "    credenciales ok"

cd "$ENTORNO"
terraform init -input=false -backend-config=backend.hcl >/dev/null

if [ -z "$(terraform state list 2>/dev/null)" ]; then
  printf '\n\033[1;32mNo hay nada que destruir.\033[0m El estado esta vacio.\n'
  exit 0
fi

# Se guarda AHORA, mientras la red existe: despues no hay de donde sacarlo.
VPC=$(terraform output -raw vpc_id 2>/dev/null || echo "")
CLUSTER=$(terraform output -raw nombre_cluster 2>/dev/null || echo "")

# --------------------------------------------------------------------------
paso "2/5  Quitando la aplicacion de Kubernetes"

if [ -n "$CLUSTER" ] && aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1

  CONTEXTO="$(kubectl config current-context 2>/dev/null || echo "")"
  case "$CONTEXTO" in
    *":cluster/$CLUSTER")
      echo "    contexto: $CONTEXTO"
      cd "$RAIZ"
      kubectl delete -k kubernetes-manifests/ --ignore-not-found=true --wait=true || true
      cd "$ENTORNO"
      echo "    esperando a que el CNI devuelva las interfaces..."
      sleep 60
      ;;
    *)
      echo "    AVISO: kubectl apunta a '$CONTEXTO', no al cluster. No borro nada"
      echo "    para no tocar otro cluster por error. Puede que queden residuos."
      ;;
  esac
else
  echo "    el cluster ya no existe, no hay nada que quitar"
fi

# --------------------------------------------------------------------------
barrer_residuos() {
  [ -n "$VPC" ] || VPC=$(aws ec2 describe-vpcs --filters Name=tag:Proyecto,Values=boutique \
      --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -v None || echo "")
  [ -n "$VPC" ] || { echo "    no encuentro la VPC, nada que barrer"; return; }

  # Interfaces sueltas: las del CNI y las que dejo el ELB al borrarse.
  for eni in $(aws ec2 describe-network-interfaces \
        --filters Name=vpc-id,Values="$VPC" Name=status,Values=available \
        --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null); do
    echo "    borrando interfaz $eni"
    aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
  done

  # Grupos de seguridad que no son de Terraform. Si alguno esta todavia en uso,
  # AWS lo rechaza y no pasa nada: el siguiente intento lo vuelve a probar.
  for sg in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null); do
    NOMBRE=$(aws ec2 describe-security-groups --group-ids "$sg" \
        --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null)
    case "$NOMBRE" in
      k8s-*|eks-cluster-sg-*)
        echo "    borrando grupo de seguridad $sg ($NOMBRE)"
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
        ;;
    esac
  done
}

paso "3/5  Destruyendo la infraestructura"

DESTRUIDO=0
for INTENTO in 1 2 3; do
  echo "    intento $INTENTO de 3"
  if terraform destroy -auto-approve; then
    DESTRUIDO=1
    break
  fi
  paso "4/5  El destroy fallo. Barriendo lo que Kubernetes dejo (intento $INTENTO)"
  barrer_residuos
  echo "    esperando a que AWS libere lo que acabo de soltar..."
  sleep 90
done

# --------------------------------------------------------------------------
paso "5/5  Comprobando"

RESTO="$(terraform state list 2>/dev/null)"
if [ "$DESTRUIDO" = "1" ] && [ -z "$RESTO" ]; then
  printf '\n\033[1;32mListo.\033[0m No queda nada cobrando.\n\n'
  exit 0
fi

cat >&2 <<AYUDA

Quedaron recursos sin destruir:

$RESTO

Mira que hay dentro de la VPC y quien es el dueno:

  VPC=$VPC
  aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=\$VPC \\
    --query "NetworkInterfaces[].[NetworkInterfaceId,Status,Description]" --output table
  aws ec2 describe-security-groups --filters Name=vpc-id,Values=\$VPC \\
    --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" --output table

Una VPC y sus subredes no cuestan nada, asi que no hay urgencia: lo caro
(cluster, nodos, balanceador) se destruye primero por dependencias. Vuelve a
correr este script dentro de unos minutos.

AYUDA
exit 1
