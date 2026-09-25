#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Crea los tickets del plan de versionado (docs/VERSIONADO.md).
#
# Un ticket = una version. Cada uno dice que archivos toca y que etiqueta sale
# de el, para que al abrirlo no haya que recordar el plan entero.
#
#   ./scripts/crear-issues-versionado.sh
#
# Requiere gh autenticado. Corre desde la raiz del repositorio.
# Los numeros reales los asigna GitHub; al final imprime el mapa.
# -----------------------------------------------------------------------------
set -euo pipefail

REPO="branToRep/microservices-demo"

crear() {
  local version="$1" titulo="$2" archivos="$3" porque="$4"
  local n
  n=$(gh issue create --repo "$REPO" \
    --title "$titulo" \
    --body "$(cat <<CUERPO
**Versión que sale de este ticket:** \`$version\`

**Archivos que toca**
$archivos

**Por qué**
$porque

---
### Para cerrarlo
- [ ] La rama sale de \`main\` actualizado (\`git checkout main && git pull\`)
- [ ] Los cambios están commiteados con Conventional Commits
- [ ] La entrada de \`CHANGELOG.md\` va en este mismo PR
- [ ] El PR dice \`Closes #<este numero>\`
- [ ] Tras fusionar: \`git tag -a $version\` y \`gh release create $version\`

Plan completo en [\`docs/VERSIONADO.md\`](docs/VERSIONADO.md).
CUERPO
)" --label "enhancement" 2>/dev/null | grep -oE '[0-9]+$')
  printf '  %-9s #%-4s %s\n' "$version" "$n" "$titulo"
}

echo "Creando los tickets del plan de versionado..."
echo

crear "v1.0.1" "Convencion de versionado y CHANGELOG" \
"- \`CHANGELOG.md\` (nuevo)
- \`docs/VERSIONADO.md\` (nuevo)" \
"El repositorio tiene que explicar su propio versionado antes de seguir creciendo."

crear "v1.0.2" "Mapa de la infraestructura" \
"- \`docs/infra.md\` (nuevo)" \
"Desglose archivo por archivo de \`infra/\`: que hace cada uno y que se rompe si falta."

crear "v1.1.0" "Backend parcial: sacar el bucket del codigo" \
"- \`infra/aws/envs/dev/backend.hcl.ejemplo\` (nuevo)
- \`infra/aws/envs/dev/backend.tf\` (se le quitan bucket y region)" \
"Los nombres de bucket son unicos en todo AWS. Mientras este escrito a fuego, nadie mas puede correr el proyecto sin editar codigo. Es el bloqueo principal de reproducibilidad."

crear "v1.1.1" "Fijar las versiones de Terraform y de Kubernetes" \
"- \`infra/aws/envs/dev/versions.tf\` (\`>= 1.10\` pasa a \`~> 1.10\`)
- \`infra/aws/envs/dev/variables.tf\` (\`version_kubernetes\` deja de ser null)" \
"Tal como esta, dentro de seis meses EKS elige otra version y dentro de dos anios alguien corre Terraform 2.x. Ninguna de las dos reproduce lo que la etiqueta promete."

crear "v1.2.0" "Script levantar.sh" \
"- \`scripts/aws/levantar.sh\` (nuevo)" \
"Un solo comando: comprueba credenciales, corre init y apply, apunta kubectl al cluster correcto, aplica los manifiestos e imprime la URL."

crear "v1.3.0" "Script apagar.sh" \
"- \`scripts/aws/apagar.sh\` (nuevo)" \
"Borra Kubernetes ANTES que AWS. Es el orden que evita que los balanceadores creados por el controlador dejen interfaces de red colgadas y el destroy falle con DependencyViolation."

crear "v1.3.1" "Borrar los flujos heredados de Google" \
"- se borran 9 archivos de \`.github/workflows/\` (ci-main, ci-pr, cleanup, deploy-pr, helm-chart-ci, kubevious, kustomize-build-ci, make-release, terraform-validate-ci)" \
"Son de la infraestructura de Google y fallan en cada push. Un CI que siempre esta en rojo deja de avisar de nada."

crear "v1.4.0" "CI de Terraform en cada PR" \
"- \`.github/workflows/terraform-ci.yml\` (nuevo)" \
"fmt -check, validate y plan en cada PR, con el plan comentado en el propio PR. Es lo que hace que se revise el cambio de infraestructura antes de aplicarlo."

crear "v1.4.1" "Proteger la rama main" \
"- \`docs/PROTECCION-RAMAS.md\` (nuevo, con el comando de gh api)" \
"Sin proteccion, un push --force sobre main reescribe el historial. Eso si destruye trabajo, a diferencia de borrar ramas fusionadas."

crear "v1.5.0" "Prueba en clon limpio" \
"- \`docs/PRUEBA-CLON-LIMPIO.md\` (nuevo)" \
"Clonar en otra carpeta o en otra maquina y levantar sin editar nada. Si falla, faltan tickets de la serie 1.x. Es el hito entregable."

crear "v1.6.0" "Publicar nuestras imagenes en GHCR" \
"- \`.github/workflows/publicar-imagenes.yml\` (nuevo)" \
"Sin esto el frontend desplegado es la imagen publica de Google y no tiene nada nuestro. --platform linux/amd64: el Mac es arm64 y los nodos amd64."

crear "v1.7.0" "Desplegar wishlistservice en el cluster" \
"- \`kubernetes-manifests/wishlistservice.yaml\`
- \`kubernetes-manifests/redis-wishlist.yaml\` (nuevo)
- \`kubernetes-manifests/kustomization.yaml\` (anadir los dos)" \
"El servicio corre pero todavia nadie lo ve. Se despliega antes que el frontend para poder probarlo aislado."

crear "v2.0.0" "Frontend propio con listas de deseos" \
"- \`kubernetes-manifests/frontend.yaml\` (apuntar a nuestra imagen de GHCR)" \
"MAYOR: cambia lo que la tienda hace. Sin tocar AWS: se publica la imagen, el despliegue se actualiza solo y la pagina cambia en la misma URL. Es la demostracion del CI/CD."

crear "v2.1.0" "Recuperar el esquema de usuarios" \
"- \`src/userservice/schema.sql\`" \
"La rama feat/user-database-schema sigue sin fusionar y trae el commit 11e4b33e."

crear "v2.2.0" "Servicio de usuarios" \
"- \`src/userservice/\` (main.go, accounts.go, sessions.go, redis.go, migrate.go, Dockerfile)
- \`protos/user.proto\`" \
"El servicio no existe en el repositorio todavia."

crear "v2.3.0" "Desplegar userservice en el cluster" \
"- \`kubernetes-manifests/userservice.yaml\` (nuevo)
- \`kubernetes-manifests/postgres.yaml\` (nuevo)
- \`kubernetes-manifests/kustomization.yaml\`" \
"Mismo patron que wishlist: primero el servicio aislado, despues la interfaz."

crear "v3.0.0" "Inicio de sesion en la tienda" \
"- \`kubernetes-manifests/frontend.yaml\`" \
"MAYOR: la misma URL ahora permite registrarse e iniciar sesion."

echo
echo "Listo. Usa los numeros REALES de arriba para las ramas: feat/<numero>-<slug>"
