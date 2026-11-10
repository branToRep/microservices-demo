# 0025 · Eliminar la cuenta: contrasena otra vez, sesiones primero, una sola sentencia

- **Estado:** aceptada
- **Issues:** #133 (v3.1.0)

## Contexto

La 3.0.0 dejo registrarse, entrar, editar el perfil, cambiar la contrasena y
salir, pero no borrar la cuenta. El contrato del `userservice` lo excluia a
proposito ("No additional functions"). Quien se registra deberia poder irse sin
pedirselo a nadie, y llevarse sus datos.

Una cuenta deja rastro en cuatro sitios, y no comparten transaccion:

| Donde | Que | Llave |
|---|---|---|
| Postgres, `users` | correo, hash, nombre, direccion | el id |
| Postgres, `login_attempts` | el correo y sus fallos | el correo |
| `redis-sessions` | cada token y el indice de tokens | el token y el id |
| `redis-cart` | el carrito de la cuenta (desde la 3.0.0) | el id |

## Decision

1. **Un RPC nuevo, `DeleteUser`, que pide la contrasena otra vez**, como
   `ChangePassword`. Una sesion abierta en un navegador ajeno no basta para
   borrar la cuenta de nadie. El frontend pide ademas una casilla marcada, y la
   comprueba en el servidor: el atributo `required` solo lo aplica el navegador.
2. **Primero se cierran todas las sesiones, despues se borra la fila.** Si
   cerrar las sesiones falla, no se borra nada y la persona reintenta. En el
   orden contrario un fallo dejaria tokens vivos que se traducen a una cuenta
   que ya no existe.
3. **`users` y `login_attempts` se borran en una sola sentencia**, con dos CTE
   que modifican datos (`WITH ... DELETE ... RETURNING`). Postgres las aplica
   juntas o ninguna, y el correo no se queda en el contador despues de la baja.
4. **Las sesiones se cierran otra vez despues de borrar**, por si alguien entro
   entre el paso 2 y el 3. Si este segundo barrido falla, la cuenta ya se borro
   y eso vale; queda en el registro.
5. **El frontend vacia el carrito** de la cuenta despues de borrarla, con el
   `EmptyCart` de siempre. Si falla, la cuenta ya no existe y nadie volvera a
   pedir ese carrito: solo se registra.
6. **Una sesion cuya cuenta ya no existe se trata como cerrada.** Si `GetUser`
   o `DeleteUser` responden `NotFound`, el frontend cierra la sesion en el
   servidor, borra la cookie y lleva a *Entrar*, en vez de una pagina de error.
7. Al terminar, la persona llega a *Entrar* con el aviso "Tu cuenta se
   eliminó".

## Lo que esto NO cubre, dicho sin rodeos

- **Un hueco de milisegundos.** Un inicio de sesion que leyo la cuenta antes
  del borrado y abre su sesion despues del segundo barrido deja un token que
  apunta a nada. Exige la contrasena correcta en ese mismo instante, y ese
  token no sirve para nada: la decision 6 lo cierra en cuanto se usa. Cerrarlo
  del todo pediria que `ValidateSession` consultara Postgres en cada peticion.
- **Las listas de deseos no se borran.** Son del navegador, no de la cuenta
  (ADR 0024), y caducan solas a las 48 h. La pagina lo dice.
- **Una contrasena mala al borrar no cuenta para el bloqueo**, igual que al
  cambiarla. Las dos piden una sesion abierta y cuestan un bcrypt por intento,
  pero quien tenga una sesion robada puede probar contrasenas sin limite. Queda
  como mejora en el CHANGELOG.
- **Una sesion que no entro al indice no se cierra.** Si el `SADD` fallo al
  abrirla (`crearSesion` lo tolera), ni `ChangePassword` ni `DeleteUser` la
  ven. Caduca sola, y apunta a una cuenta que ya no existe (decision 6).

## Alternativas descartadas

- **Borrado logico** (una columna `deleted_at`). Conserva justo lo que la
  persona pidio quitar, y obliga a filtrar en cada consulta. Sin una razon
  legal para guardar nada, no hay motivo.
- **Borrar desde el frontend llamando a cada almacen.** El frontend no tiene,
  ni debe tener, acceso a Postgres ni al Redis de sesiones. El carrito si lo
  vacia el, porque el carrito ya es suyo.
- **Borrar primero y cerrar sesiones despues** (un solo barrido). Mas simple,
  pero un fallo entre los dos pasos deja sesiones huerfanas sin aviso.
- **Una transaccion que incluya Redis.** No existe: son dos sistemas. El orden
  de la decision 2 y el segundo barrido son lo mas cerca que se llega sin
  meter las sesiones en Postgres, que la 2.1.0 descarto (ADR 0021).

## Consecuencias

- El `.proto` gana un RPC y un mensaje. Es compatible hacia atras: un cliente
  viejo no lo llama, y los stubs se regeneran con el script de siempre
  (ADR 0016).
- La cuenta borrada libera su correo: se puede volver a registrar, con un id
  nuevo y el carrito vacio.
- Como Postgres vive en un `emptyDir` (ADR 0023), las cuentas tampoco
  sobreviven a un reinicio del pod ni a `apagar.sh`. Esto no cambia con la
  3.1.0.
