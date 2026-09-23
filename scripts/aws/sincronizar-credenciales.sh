set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

for v in aws_access_key_id aws_secret_access_key aws_session_token; do
  val=$(aws configure get "$v")
  [ -z "$val" ] && { echo "Falta $v en ~/.aws/credentials"; exit 1; }
  gh secret set "$(echo "$v" | tr '[:lower:]' '[:upper:]')" --body "$val"
done
echo "credenciales configudradasproceso"
