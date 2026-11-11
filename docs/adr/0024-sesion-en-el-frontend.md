# 0024 · Sesion en el frontend: cookie, CSRF y una tienda sin TLS

- **Estado:** aceptada
- **Issues:** #65 (y lo que hereda del #22 y del #25)

## Contexto

El `userservice` emite tokens de sesion opacos de 43 caracteres y los guarda en
Redis (#63, ADR 0021). Falta que el frontend los use: pedirlos al entrar,
guardarlos en el navegador, y validarlos en cada visita.

El #25 pide la cookie endurecida con `HttpOnly`, `Secure` y `SameSite`. El #22
pide el middleware de sesion y la proteccion CSRF.

Y hay una restriccion que lo condiciona todo: **la tienda se sirve por HTTP.**
El balanceador de `infra/aws/envs/dev` no tiene certificado.

## Decision

1. **La cookie `shop_sesion`** lleva el token con `HttpOnly` (ningun JavaScript
   de la pagina puede leerla), `SameSite=Lax` (no viaja en un POST desde otro
   sitio), una ruta explicita y como caducidad la del propio token. La marca
   `Secure` es configurable (`COOKIE_SEGURA`) y esta **apagada** mientras no
   haya TLS.
2. **CSRF con cookie doble:** un valor aleatorio en la cookie `shop_csrf` y el
   mismo valor en el campo oculto `csrf_token` de cada formulario. Otro sitio
   puede hacer que el navegador *envie* la cookie, pero no puede *leerla* para
   copiarla en el formulario. Se compara en tiempo constante y se exige en
   **todos los POST de cuentas**: entrar, registrarse, perfil, contrasena y
   salir. Los POST que ya existian (carrito, listas, compra) no lo llevan:
   `SameSite=Lax` impide que la cookie de sesion viaje en un POST desde otro
   sitio, asi que un ataque desde fuera actua como anonimo y no toca ninguna
   cuenta.
3. **El carrito pasa a ser de la cuenta.** `cartID(r)` devuelve la cuenta si hay
   sesion y la sesion anonima si no, y es la llave del carrito en las nueve
   llamadas que lo usan. Al entrar, lo que habia en el carrito anonimo se suma
   al de la cuenta y el anonimo se vacia. Las listas de deseos **no** cambiaron
   en la 3.0.0: siguieron por navegador (`sessionID(r)`). **Corregido en la
   3.1.1:** dos cuentas que entraban desde el mismo navegador veian las mismas
   listas. Ahora usan `wishlistID(r)`, con la regla del carrito, y al entrar
   las listas anonimas pasan a la cuenta (una con el mismo nombre se junta).
4. **Salir cierra la sesion en el servidor** antes de borrar la cookie, tambien
   en el `/logout` que ya traia la tienda. Borrar solo la cookie dejaria el
   token valido en Redis hasta que caducara.
5. **Las paginas de cuentas van en castellano**, como el cableado que quito la
   1.5.1 y como los mensajes que ya devuelve el `userservice`. El resto de la
   tienda sigue en ingles, que es como la trae Google.

## Lo que esto NO protege, dicho sin rodeos

- **El token viaja sin cifrar.** Quien este en el camino (la misma wifi, un
  proxy) puede copiarlo y usar la sesion hasta que caduque, en 24 horas, o hasta
  que se cierre. La contrasena, al entrar, igual. Lo mitigan que la sesion
  caduque sola, que *Salir* la revoque en el servidor, y que cambiar la
  contrasena revoque todas las demas. Lo arregla TLS en el balanceador, que es
  otro ticket.
- **El registro dice si un correo ya tiene cuenta** (`AlreadyExists`). Es como
  lo decidio el `userservice` en el #63; el inicio de sesion, en cambio, no lo
  revela: correo inexistente y contrasena mala dan el mismo mensaje.
- **El `/logout` por GET que trae Google sigue existiendo.** Un enlace desde
  otro sitio puede cerrarte la sesion. Molesto, no peligroso.

## Alternativas descartadas

- **`Secure` encendida ya.** Por HTTP el navegador no manda la cookie: el
  formulario parece funcionar, te devuelve a la portada, y no hay sesion ni
  ningun error. Peor que no tenerla, porque parece roto.
- **Token CSRF guardado en Redis (patron sincronizado).** Otro almacen y otra
  llamada por peticion para la misma proteccion que da la cookie doble.
- **Token CSRF firmado con HMAC.** Necesita un secreto del servidor: un cuarto
  secreto en Vault, con su ruta en la politica, su linea en Ansible y su entrada
  en el chart, sin ventaja aqui sobre la cookie doble.
- **El token de sesion en `localStorage`.** Lo puede leer cualquier JavaScript
  de la pagina; con una cookie `HttpOnly`, ninguno.
- **`SameSite=Strict`.** Al llegar desde un enlace externo (un correo, un
  buscador), la primera pagina te veria sin sesion. `Lax` ya protege los POST,
  que es lo que importa.

## Consecuencias

- Poner TLS es: certificado en el balanceador y `COOKIE_SEGURA=1`. No cambia
  nada mas del codigo.
- Cada peticion que trae cookie de sesion hace un `ValidateSession`, con un
  limite de `USER_SERVICE_TIMEOUT` (3 s por defecto). Si el servicio no
  contesta, la tienda sirve la pagina como anonima y no borra la cookie: la
  sesion vuelve sola cuando vuelve el servicio.
- Entrar, registrarse y cambiar la contrasena tienen su propio limite,
  `USER_SERVICE_TIMEOUT_CLAVES` (10 s), porque hacen bcrypt, lento a
  proposito. Si aun asi se supera, la persona ve su formulario con un aviso y un
  503, no la pagina de error. El limite general de 3 s no valia para ellas:
  medido en el cluster, cambiar la contrasena tardaba 3,1 s con 200m de CPU, que
  por eso subio a 500m.
