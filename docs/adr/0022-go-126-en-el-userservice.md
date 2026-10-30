# 0022 · El userservice usa Go 1.26, no el 1.23 del resto

- **Estado:** aceptada
- **Issues:** #63

## Contexto

Los servicios propios de este repositorio van en Go 1.23: el `wishlistservice`
lo declara en su `go.mod` y su imagen esta fijada a
`golang:1.23.4-alpine@sha256:c2333919...`. El `userservice` empezo copiando ese
`go.mod`, por simetria.

Al anadir sus dependencias la simetria se rompio sola. `bcrypt` vive en
`golang.org/x/crypto`, y las versiones actuales de los modulos `golang.org/x`
exigen Go 1.26. Mantener la directiva en 1.23 obligaba a bajar `x/net`, luego
`x/sync`, y despues `x/crypto`, a versiones de 2024 — una detras de otra, cada
una descubierta cuando la anterior se arreglaba.

## Decision

Este modulo declara `go 1.26.0` y su `Dockerfile` construye con
`golang:1.26-alpine`. El `wishlistservice` se queda en 1.23: no se toca.

**Lo unico que tiene que cumplirse es que el `go.mod` de un servicio y su propio
`Dockerfile` coincidan.** Cada servicio es un modulo de Go independiente, con su
`go.mod`, su `go.sum` y su imagen. Nada obliga a que dos modulos distintos usen
la misma version del lenguaje, y creer lo contrario fue lo que llevo a la
persecucion de dependencias.

El motivo de fondo: **este es el servicio que hashea contrasenas**. Fijar
`golang.org/x/crypto` hacia atras, en el unico servicio del proyecto que hace
criptografia, para cuadrar un numero que nadie exige, es pagar en seguridad por
una simetria decorativa.

## Alternativas descartadas

- **Quedarse en 1.23 bajando dependencias.** Mantiene los dos servicios
  iguales. A cambio, el servicio de cuentas carga bibliotecas de criptografia de
  2024, y la pelea se repite con cada dependencia nueva que se anada.

- **Subir tambien el `wishlistservice` a 1.26.** Dejaria el repositorio
  homogeneo. Se descarta por alcance: ese servicio funciona, no lo pide nadie, y
  tocarlo desde el ticket del `userservice` mete en un PR un cambio que no tiene
  nada que ver con el. Si algun dia se sube, sera por su propio motivo.

- **Vendorizar las dependencias** (`go mod vendor`) para congelarlas. Resuelve
  la reproducibilidad, que no era el problema: el problema era que versiones
  nuevas exigen un lenguaje nuevo. Ademas hincha el repositorio.

## Consecuencias

- **Hay dos versiones de Go en el repositorio.** Quien lea los dos servicios
  seguidos va a notarlo, y por eso existe este documento.

- **La pareja `go.mod` + `Dockerfile` hay que revisarla por servicio.** Si se
  separan, la maquina de quien programa compila sin problema y **la imagen falla
  en GitHub Actions**, que es el peor sitio para enterarse. No hay nada
  automatico que ate las dos: es una comprobacion de revision.

- **Falta fijar la huella de la imagen.** El resto del repositorio fija por
  digest y este `Dockerfile` todavia no. Esta anotado en el propio archivo, con
  el comando para sacarla.
