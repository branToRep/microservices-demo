#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Crea el bucket donde vive el estado de Terraform.
#
# NO lo hace Terraform a proposito: la politica de la organizacion del
# laboratorio (SCP) deniega s3:GetBucketObjectLockConfiguration, y el proveedor
# de AWS hace esa consulta al releer el bucket despues de crearlo. El recurso se
# crea bien y el apply falla igual. Con la CLI no ocurre.
#
# Se ejecuta UNA VEZ. Si el laboratorio borra la cuenta, se vuelve a ejecutar.
# -----------------------------------------------------------------------------
set -euo pipefail
BUCKET="${1:-boutique-tfstate-devops}"
REGION="${2:-us-east-1}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "El bucket $BUCKET ya existe."
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  echo "Creado $BUCKET."
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled || echo "AVISO: versionado denegado por la SCP"

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  || echo "AVISO: cifrado denegado por la SCP"

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  || echo "AVISO: bloqueo de acceso publico denegado por la SCP"

echo
echo "Pon este nombre en infra/aws/envs/dev/backend.hcl:"
echo "  bucket = \"$BUCKET\""
