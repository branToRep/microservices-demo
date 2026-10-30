# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Go 1.26 y no 1.23 como el wishlistservice: ver el ADR 0022. En resumen, este
# servicio hashea contrasenas, y quedarse en 1.23 obligaba a fijar golang.org/x
# —criptografia incluida— en versiones de 2024.
#
# Fijada por huella, como el resto del repositorio: la etiqueta '1.26-alpine' se
# mueve cuando publican un parche, el digest no. Asi dos personas construyen
# exactamente lo mismo. Para actualizarla a proposito:
#
#   docker pull golang:1.26-alpine
#   docker inspect --format='{{index .RepoDigests 0}}' golang:1.26-alpine
FROM --platform=$BUILDPLATFORM golang:1.26-alpine@sha256:a2012b4a1d1f9f7e9f44e0d39b805a901e856b1dd80b4e6ee4338db547050308 AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src

# Las dependencias primero: esta capa solo se rehace cuando cambian go.mod o
# go.sum, asi que editar el codigo no vuelve a descargarlas.
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# Skaffold passes in debug-oriented compiler flags
ARG SKAFFOLD_GO_GCFLAGS
# CGO_ENABLED=0 da un binario estatico, que es lo que permite la imagen final
# 'scratch': sin libc dentro, un binario dinamico no arrancaria.
#
# schema.sql NO se copia a la imagen final: va dentro del binario por el
# //go:embed de migrate.go.
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 go build -gcflags="${SKAFFOLD_GO_GCFLAGS}" -o /go/bin/userservice .

FROM scratch
WORKDIR /src
COPY --from=builder /go/bin/userservice /src/server

# Definition of this variable is used by 'skaffold debug' to identify a golang binary.
ENV GOTRACEBACK=single

EXPOSE 8080
ENTRYPOINT ["/src/server"]
