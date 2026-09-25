#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Genera el codigo Go de protos/wishlist.proto para los dos servicios que lo usan.
#
#   ./scripts/generar-protos.sh
#
# NO hace falta tener protoc ni los plugins instalados: todo corre dentro de un
# contenedor. Lo unico que se necesita es Docker.
#
# POR QUE ESTE SCRIPT EXISTE
#
# El codigo de wishlist.proto no estaba en el repositorio y estaba ademas en el
# .gitignore, asi que ni el frontend ni el wishlistservice compilaban en un clon
# limpio: sus main.go importan un paquete "genproto" que no existia. Se descubrio
# al montar la publicacion de imagenes (#59).
#
# Ahora el codigo generado SI se versiona, por coherencia: el repositorio ya
# versiona el de Google (src/frontend/genproto/demo.pb.go). Ver el ADR 0016.
#
# Se vuelve a correr solo cuando cambia protos/wishlist.proto.
# -----------------------------------------------------------------------------
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

# Fijadas para que dos personas obtengan byte a byte lo mismo. Son las mismas
# con las que se genero el codigo de Google que ya esta en el repositorio.
VERSION_GO=1.23-alpine
VERSION_PROTOC_GEN_GO=v1.34.2
VERSION_PROTOC_GEN_GO_GRPC=v1.5.1

command -v docker >/dev/null || {
  echo "Hace falta Docker. Abre Docker Desktop y vuelve a intentarlo." >&2
  exit 1
}
docker info >/dev/null 2>&1 || {
  echo "Docker esta instalado pero no responde. Abre Docker Desktop." >&2
  exit 1
}

echo "==> Generando desde protos/wishlist.proto"

docker run --rm \
  -v "$RAIZ":/work -w /work \
  -e GOTOOLCHAIN=local \
  "golang:${VERSION_GO}" sh -eu -c "
    apk add --no-cache protobuf >/dev/null
    go install google.golang.org/protobuf/cmd/protoc-gen-go@${VERSION_PROTOC_GEN_GO}
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@${VERSION_PROTOC_GEN_GO_GRPC}
    export PATH=\"\$PATH:\$(go env GOPATH)/bin\"

    for destino in src/frontend/genproto src/wishlistservice/genproto; do
      mkdir -p \"\$destino\"
      protoc --proto_path=protos \
        --go_out=\"\$destino\"      --go_opt=paths=source_relative \
        --go-grpc_out=\"\$destino\" --go-grpc_opt=paths=source_relative \
        protos/wishlist.proto
      echo \"    \$destino\"
    done
  "

echo
echo "Generado:"
ls -1 src/frontend/genproto/wishlist*.go src/wishlistservice/genproto/*.go 2>/dev/null | sed 's/^/  /'
echo
echo "Estos archivos SI se versionan. Anadelos con:"
echo "  git add src/frontend/genproto src/wishlistservice/genproto"
