#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Levanta la maquina de Vault y la configura. Desde cero, o encima de lo que ya
# haya: Terraform solo crea lo que falta y Ansible solo cambia lo que difiere.
#
#   bash scripts/aws/levantar-vault.sh
#
# Deja Vault instalada, con TLS y la UI, SIN INICIALIZAR. 'vault operator init'
# es manual a proposito: genera las llaves de desellado (ADR 0019).
#
# Antes, una vez por cuenta: el bucket del estado y envs/dev/backend.hcl (ver
# docs/infra.md). Una vez por portatil: la llave ~/.ssh/boutique-vault, la AWS
# CLI, el session-manager-plugin y Ansible (ver ansible/README.md).
#
# NO hay un apagar-vault.sh, y es deliberado. Destruir esta maquina borra Vault
# entera, llaves incluidas. Eso no puede estar a un comando de distancia: se hace
# a mano con 'terraform destroy', leyendo lo que va a borrar.
# -----------------------------------------------------------------------------
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTORNO="$RAIZ/infra/aws/envs/vault"
BACKEND="$RAIZ/infra/aws/envs/dev/backend.hcl"
LLAVE="$HOME/.ssh/boutique-vault"

paso() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
alto() { printf '\n\033[1;31mALTO:\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
paso "1/6  Comprobando lo que hace falta en esta maquina"

for herramienta in terraform aws session-manager-plugin ansible-playbook ansible-galaxy; do
  command -v "$herramienta" >/dev/null || alto "Falta '$herramienta'. Ver ansible/README.md (Requisitos)."
done
[ -f "$LLAVE" ] && [ -f "$LLAVE.pub" ] || alto "Falta la llave SSH $LLAVE. Creala una vez con:
       ssh-keygen -t ed25519 -f $LLAVE -C boutique-vault"
[ -f "$BACKEND" ] || alto "Falta $BACKEND (el nombre de TU bucket). Ver docs/infra.md."

# Igual que levantar.sh: una clave repetida metia un salto de linea en el valor.
leer_clave() {
  local clave="$1" archivo="$2" n
  n=$(grep -cE "^[[:space:]]*${clave}[[:space:]]*=" "$archivo" || true)
  [ "$n" -gt 1 ] && alto "backend.hcl declara '${clave}' $n veces. Deja una sola linea."
  sed -nE "s/^[[:space:]]*${clave}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" "$archivo" | head -1
}
BUCKET=$(leer_clave bucket "$BACKEND")
REGION=$(leer_clave region "$BACKEND"); REGION="${REGION:-us-east-1}"
[ -n "$BUCKET" ] || alto "backend.hcl no declara ningun bucket."
echo "    ok (bucket: $BUCKET)"

# --------------------------------------------------------------------------
paso "2/6  Comprobando que las credenciales sirvan"

# Leer el bucket, y no 'sts get-caller-identity': esa responde igual con
# credenciales que la politica del laboratorio ya cancelo (ver levantar.sh).
aws s3 ls "s3://$BUCKET/" >/dev/null 2>&1 || alto "No puedo leer s3://$BUCKET/.
       O la sesion del laboratorio termino (vuelve a pegar las TRES lineas en
       ~/.aws/credentials), o el bucket no existe en ESTA cuenta:
         bash infra/aws/bootstrap/crear-bucket-estado.sh $BUCKET"
echo "    ok"

# --------------------------------------------------------------------------
paso "3/6  Terraform: la maquina"
cd "$ENTORNO"
export TF_REGISTRY_CLIENT_TIMEOUT="${TF_REGISTRY_CLIENT_TIMEOUT:-60}"

# -reconfigure: si este directorio se inicializo antes contra OTRO bucket (otra
# cuenta, otro operador), Terraform pregunta si migrar aquel estado. Aqui nunca
# se quiere: el estado de esta cuenta es el de su propio bucket.
terraform init -input=false -reconfigure -backend-config="$BACKEND" >/dev/null

# Se planifica antes de aplicar, y si el plan BORRA o REEMPLAZA algo, se para.
# Esta maquina guarda los datos de Vault en su disco: un reemplazo silencioso los
# perderia. Crear desde cero, o no cambiar nada, sigue adelante solo.
terraform plan -input=false -out=vault.tfplan >/dev/null
if terraform show -no-color vault.tfplan | grep -qE 'will be destroyed|must be replaced'; then
  terraform show -no-color vault.tfplan | grep -E '^  # .*(destroyed|replaced)' >&2 || true
  rm -f vault.tfplan
  alto "El plan borra o reemplaza recursos de Vault. No lo aplico solo.
       Revisalo con:  terraform -chdir=infra/aws/envs/vault plan"
fi
terraform apply -input=false vault.tfplan
rm -f vault.tfplan

ID=$(terraform output -raw id_instancia)
VAULT_ADDR=$(terraform output -raw vault_addr)

# --------------------------------------------------------------------------
paso "4/6  Encendiendo la maquina si el laboratorio la detuvo"
ESTADO=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text)
if [ "$ESTADO" = "stopped" ]; then
  aws ec2 start-instances --region "$REGION" --instance-ids "$ID" >/dev/null
fi
aws ec2 wait instance-running --region "$REGION" --instance-ids "$ID"
echo "    $ID en marcha"

# --------------------------------------------------------------------------
paso "5/6  Esperando a que la maquina se registre en SSM"
# Recien creada o recien encendida, el agente tarda uno o dos minutos. Ansible
# entra por SSM: sin esta espera, la primera tarea falla con TargetNotConnected.
for _ in $(seq 1 40); do
  PING=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)
  [ "$PING" = "Online" ] && break
  printf '.'
  sleep 10
done
echo
[ "${PING:-}" = "Online" ] || alto "$ID no aparece en SSM tras ~7 minutos.
       Comprueba que lleva el perfil LabInstanceProfile (ADR 0020)."
echo "    ok"

# --------------------------------------------------------------------------
paso "6/6  Ansible: el sistema y Vault"
cd "$RAIZ/ansible"
# Explicito: en WSL, /mnt/c es escribible por todos y Ansible ignoraria el
# ansible.cfg del directorio (ver ansible/README.md).
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
ansible-galaxy collection install -r requirements.yml >/dev/null
ansible-playbook site.yml

# --------------------------------------------------------------------------
printf '\n\033[1;32mListo.\033[0m  Vault responde en %s\n\n' "$VAULT_ADDR"
cat <<SIGUIENTE
Para la CLI:
  export VAULT_ADDR=$VAULT_ADDR
  export VAULT_CACERT=$HOME/.vault-boutique/ca.crt
  vault status

Si la maquina es NUEVA, la CA tambien lo es: vuelve a instalar ca.crt en
Windows (y borra la anterior). Ver ansible/README.md.
SIGUIENTE
