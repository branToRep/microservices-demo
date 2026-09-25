# 0017 · El frontend va sin cuentas hasta la v3.0.0

- **Estado:** aceptada
- **Issues:** #59

## Contexto
El PR #35 («Setup frontend connections wishlist issue #12») metio en `main` el
**cableado** de cuentas de usuario sin la implementacion: ocho rutas
(`/login`, `/register`, `/account`…), los campos `userSvcAddr`/`userSvcConn`, el
middleware `withUser`, las llamadas a `currentUser`, `authToken` y
`csrfFromRequest`, y el menu de cuenta en `header.html`.

Los archivos que sostienen todo eso **nunca han estado en el repositorio**:
`auth.go`, `merge.go`, `login.html`, `register.html`, `account.html` y
`src/userservice/` tienen cero commits en toda la historia. Comprobable con:

```bash
git log --oneline --all -- src/frontend/auth.go   # no devuelve nada
```

Consecuencia: **el frontend no compila desde el PR #35**. Nadie lo noto porque
la tienda desplegada usa la imagen publica de Google, asi que nuestro frontend
nunca se construyo ni se ejecuto. Salio a la luz al montar la publicacion de
imagenes, que es la primera vez que algo lo compila de verdad.

## Decision
Se quita el cableado de cuentas. La v2.0.0 publica un frontend con **listas de
deseos y nada mas**: sin rutas de cuenta, sin menu de perfil, sin boton "Entrar".

Todo vuelve en la v3.0.0, y entonces completo: el cableado **y** `auth.go`,
`merge.go`, las tres plantillas y el `src/userservice/` desplegado.

Donde estaban las rutas queda un comentario que dice que llega en la v3.0.0 y con
que archivos, para que el hueco se lea como intencional.

## Alternativas descartadas
- **Traer ya `auth.go`, `merge.go` y las plantillas.** El frontend compilaria y
  arrancaria (la conexion gRPC no bloquea), pero el boton "Entrar" apareceria y
  daria error hasta que el userservice estuviera desplegado. Una funcion visible
  y rota es peor que una funcion ausente.
- **Adelantar los tickets del userservice y desplegar todo junto en la v2.0.0.**
  Funciona, y fusiona dos versiones en una. El proyecto existe para demostrar
  entrega incremental: perder un escalon cuesta mas que lo que ahorra.

## Consecuencias
- La v3.0.0 crece: ademas de anadir el userservice, restaura lo que esta ADR
  quita. El diff de esa version sera el mas grande del proyecto.
- El riesgo es olvidar la mitad al restaurar. Lo mitiga que el commit que quita
  el cableado es uno solo y localizable:
  `git log --oneline -S viewLoginHandler -- src/frontend/main.go`.
- `git revert` de ese commit devuelve el cableado en un paso, aunque sigue
  haciendo falta anadir a mano los archivos que nunca estuvieron.
