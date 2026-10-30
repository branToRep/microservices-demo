# 0021 · El contador de intentos vive en Postgres; las sesiones siguen en Redis

- **Estado:** aceptada
- **Issues:** #63
- **Completa a:** la decision escrita en `src/userservice/schema.sql` (v2.1.0)

## Contexto

La v2.1.0 trajo el esquema de `users` y dejo escrita, al final del archivo, una
decision sobre donde viven las sesiones:

> Las sesiones NO viven aqui: viven en Redis, que expira solo. Una sesion
> perdida obliga a volver a entrar; una cuenta perdida deja a alguien fuera
> para siempre.

Esa decision sigue en pie y este ADR no la reabre. Pero **no dice nada del
contador de intentos fallidos**, y la lista del #63 lo pide: *"sesiones con
limite de intentos"*, heredado del #17 del plan original.

Son dos estados con naturalezas distintas, y de ahi que no vayan al mismo sitio:

| | Sesion | Contador de intentos |
|---|---|---|
| Se lee | en cada peticion autenticada | solo al fallar un login |
| Caduca | sola, en minutos u horas | tras una ventana de bloqueo |
| Si se pierde | vuelves a entrar: molesto | el atacante recupera sus intentos: **es el fallo que el control existe para impedir** |

## Decision

1. **Las sesiones siguen en Redis**, como decidio la v2.1.0. El contrato encaja
   sin forzarlo: `ValidateSession` es una lectura por clave y `Logout` es un
   borrado.
2. **El contador de intentos vive en Postgres**, en una tabla nueva de
   `schema.sql`.

Un limite de intentos que se reinicia cuando se reinicia el pod no es un limite:
basta esperar un reinicio para volver a tener todos los intentos. Un control de
seguridad que se puede borrar esperando no es un control de seguridad.

Se cuenta **por correo, exista o no la cuenta**. Si solo se contaran los intentos
contra cuentas reales, el servicio responderia distinto segun existiera el correo
o no, y eso revela que correos estan registrados.

## Alternativas descartadas

- **El contador en Redis, junto a las sesiones.** Un solo sitio y caducidad
  gratis. Descartada por lo de arriba: es volatil, y esa volatilidad vacia el
  control. Redis guarda lo que da igual perder; esto no da igual.

- **El contador como columna de `users`.** Mas simple, una columna y ya. No
  sirve: los intentos contra correos que no existen no tendrian donde contarse,
  y volvemos a filtrar que cuentas hay.

- **Las sesiones tambien en Postgres.** Permitiria crear la sesion y limpiar el
  contador en una sola transaccion. No compensa reabrir una decision tomada y
  escrita, y obligaria a limpiar a mano lo que Redis caduca solo.

- **Token firmado sin estado (JWT) en vez de sesiones.** Quitaria la busqueda
  por peticion. **Lo impide el contrato**: `protos/user.proto` define
  `ValidateSession` como *"translates session token to an identity"* y el
  `session_token` como *"obscured"* — un token opaco que se resuelve contra algo
  guardado. Y `Logout` *"terminates session"*: con un token firmado, cerrar
  sesion no termina nada, el token robado vale hasta caducar. Cambiarlo exigiria
  tocar el proto, que es alcance cerrado desde el #14.

## Consecuencias

- **Son dos almacenes para una funcion.** El `userservice` habla con Postgres y
  con Redis. A cambio, cada estado esta donde su naturaleza pide.

- **Crear la sesion y poner el contador a cero no es atomico.** Ocurren en
  sistemas distintos. El orden importa: primero la sesion en Redis, y solo si
  esa sale bien se limpia el contador. Al reves, un fallo entre las dos dejaria
  el contador limpio sin sesion creada, que es el lado que regala intentos.

- **Hay que limpiar los bloqueos vencidos.** No caducan solos como en Redis: o
  se filtran al leer (`locked_until < now()`) o los borra un job.

- **La sesion anonima del carrito sigue siendo otra cosa.** El frontend ya usa
  una cookie propia (`sessionID`) para el carrito en `redis-cart`, sin estado en
  servidor. No se mezcla con esta: fundir el carrito anonimo al iniciar sesion
  es trabajo del #65 (`merge.go`).
