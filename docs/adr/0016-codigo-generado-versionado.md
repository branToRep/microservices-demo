# 0016 · El codigo gRPC generado se versiona

- **Estado:** aceptada
- **Issues:** #59

## Contexto
Al montar la publicacion de imagenes se descubrio que **ni el frontend ni el
wishlistservice compilan en un clon limpio**. Los dos importan un paquete
`genproto` con los tipos de `protos/wishlist.proto`:

```go
pb "github.com/GoogleCloudPlatform/microservices-demo/src/frontend/genproto"
pb "github.com/GoogleCloudPlatform/microservices-demo/src/wishlistservice/genproto"
```

Ese codigo no estaba en el repositorio. `src/frontend/genproto/` solo tenia el de
Google (`demo.pb.go`), sin nada de Wishlist, y `src/wishlistservice/genproto/` no
existia y estaba ademas en el `.gitignore`. Faltaban doce tipos que el frontend
usa (`WishlistServiceClient`, `CreateWishlistRequest`, `Wishlist`…).

Habia funcionado en local porque las maquinas donde se escribio el codigo tenian
el `genproto/` generado desde antes, sin versionar. Es el mismo tipo de
dependencia invisible que la prueba en clon limpio (#58) existe para cazar — solo
que esta no se detecto ahi, porque esa prueba levanta la tienda con la imagen
publica de Google y no compila nada nuestro.

## Decision
El codigo generado **se versiona**, y se quita la regla del `.gitignore`.

Se regenera con `./scripts/generar-protos.sh`, que corre `protoc` y los dos
plugins **dentro de un contenedor**: no hace falta instalar nada mas que Docker,
y las versiones del generador estan fijadas en el script para que dos personas
obtengan lo mismo.

## Alternativas descartadas
- **Generar en el flujo de CI, antes del `docker build`.** Resuelve la
  publicacion, pero deja el repositorio en un estado donde `go build` local sigue
  fallando. El defecto se esconde en vez de arreglarse.
- **Generar dentro del Dockerfile.** Hace la imagen autosuficiente, y sigue
  dejando el `go build` local roto. Ademas alarga cada construccion.
- **Seguir sin versionarlo y documentar que hay que correr `genproto.sh`.** Es lo
  que habia, y produjo exactamente este problema.

Las tres se descartan por la misma razon: el objetivo del proyecto es que otra
persona clone y todo funcione. Un paso manual obligatorio antes de compilar es
justo lo que la serie 1.x se dedico a eliminar.

## Consecuencias
- Los diffs incluiran de vez en cuando archivos generados grandes. Se aceptan:
  llevan la cabecera `DO NOT EDIT` y se revisan por el `.proto`, no linea a linea.
- Hay que acordarse de regenerar al cambiar el `.proto`. El riesgo real es que el
  codigo y el contrato se desincronicen sin que nadie lo note.
- **Es coherente con lo que ya hacia el repositorio**: `demo.pb.go` de Google
  siempre estuvo versionado. La regla del `.gitignore` para el nuestro era la
  excepcion, no la norma.
