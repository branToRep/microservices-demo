# Cómo se versiona este proyecto

La meta del versionado aquí no es burocracia: es que el repositorio **cuente la
historia paso a paso**. Alguien tiene que poder abrir la lista de versiones y
ver que primero se añadió un archivo de Terraform, después un script, después un
manifiesto — cada cosa por separado, con su ticket, su PR y su fecha.

Por eso no hay tres versiones gordas. Hay **una versión por ticket**.

---

## 1. La regla: un ticket, una versión

```
 issue #NN  →  rama feat/NN-slug  →  PR "Closes #NN"  →  squash a main  →  etiqueta vX.Y.Z
```

Cada ticket toca **pocos archivos, a veces uno solo**, y sale de ahí con su
propia etiqueta. Un ticket que añade `backend.hcl.ejemplo` es una versión. Un
ticket que añade `levantar.sh` es otra. No se juntan.

Es más granular de lo que se estila en un proyecto de producción, donde una
versión agrupa semanas de trabajo. Aquí es a propósito: **lo que se está
demostrando es el proceso**, y el proceso solo se ve si cada paso deja huella
propia. Si alguien pregunta por qué tantas versiones, esa es la respuesta.

### El ciclo completo de un ticket

```bash
# 1. La rama sale de main ACTUALIZADO. Nunca ramifiques sin comprobar
#    que el PR anterior ya se fusionó, o arrastras trabajo ajeno.
git checkout main && git pull
git checkout -b feat/49-backend-parcial

# 2. Los commits. Si el ticket toca varios archivos con propósitos
#    distintos, van en commits distintos: el diff se lee mejor.
git add infra/aws/envs/dev/backend.hcl.ejemplo
git commit -m "feat(infra): agrega el ejemplo de configuracion del backend"

git add infra/aws/envs/dev/backend.tf
git commit -m "refactor(infra): saca el nombre del bucket a configuracion parcial"

# 3. El CHANGELOG va DENTRO del mismo PR. Así cada PR se explica solo
#    y la etiqueta no necesita trabajo extra después.
git add CHANGELOG.md
git commit -m "docs: anota la version 1.1.0"

# 4. El PR
git push -u origin feat/49-backend-parcial
pr                                    # la funcion que fija la base al fork

# 5. Tras fusionar (squash), la etiqueta sobre main
git checkout main && git pull
git tag -a v1.1.0 -m "El bucket del estado ya no esta escrito a fuego"
git push origin v1.1.0
gh release create v1.1.0 --title "v1.1.0 — Backend parcial" --generate-notes
```

Ese `--generate-notes` hace que GitHub liste solo los PRs fusionados desde la
etiqueta anterior. Como cada etiqueta cubre un ticket, la nota de versión sale
siendo exactamente ese ticket.

---

## 2. Qué número sube

| Parte | Sube cuando… |
|---|---|
| **MAYOR** | cambia lo que la tienda *hace* para quien la usa |
| **MENOR** | aparece una capacidad nueva que antes no existía, sin romper nada |
| **PARCHE** | se corrige, se fija o se documenta algo que ya estaba |

Traducido a este proyecto: añadir `levantar.sh` es MENOR porque antes no se
podía levantar con un comando. Fijar `version_kubernetes` es PARCHE porque el
clúster ya se creaba, solo que de forma no reproducible. Que aparezca el botón
de listas de deseos en la tienda es MAYOR.

---

## 3. El camino completo, ticket por ticket

### Serie 1.0.x — la documentación

El repositorio se explica a sí mismo antes de seguir creciendo.

| Ver. | Ticket | Archivos que toca |
|---|---|---|
| **v1.0.0** | — | *ya está en main*: infra en Terraform + la tienda de Google sin modificar |
| **v1.0.1** | Convención de versionado | `CHANGELOG.md`, `docs/VERSIONADO.md` |
| **v1.0.2** | Mapa de la infraestructura | `docs/infra.md` |

### Serie 1.x — portabilidad

El objetivo de la serie: **que el profesor clone y levante sin editar nada**.
Cada ticket quita un obstáculo concreto.

| Ver. | Ticket | Archivos que toca | Qué desbloquea |
|---|---|---|---|
| **v1.1.0** | Backend parcial | `envs/dev/backend.hcl.ejemplo` (nuevo), `envs/dev/backend.tf` | el nombre del bucket deja de estar a fuego |
| **v1.1.1** | Fijar versiones | `envs/dev/versions.tf`, `envs/dev/variables.tf` | `~> 1.10` en vez de `>= 1.10`; `version_kubernetes` con número |
| **v1.2.0** | Script de arranque | `scripts/aws/levantar.sh` (nuevo) | pegas credenciales y corre un comando |
| **v1.3.0** | Script de apagado | `scripts/aws/apagar.sh` (nuevo) | borra Kubernetes **antes** que AWS, que es lo que evita el `DependencyViolation` |
| **v1.3.1** | Limpiar flujos heredados | borra 9 archivos de `.github/workflows/` | dejan de fallar en cada push |
| **v1.4.0** | CI de Terraform | `.github/workflows/terraform-ci.yml` (nuevo) | `fmt`, `validate` y `plan` en cada PR |
| **v1.4.1** | Proteger main | `docs/PROTECCION-RAMAS.md` (nuevo) | sin `push --force`, sin borrar main |
| **v1.5.0** | Prueba en clon limpio | `docs/PRUEBA-CLON-LIMPIO.md` (nuevo) | **el hito**: alguien más lo levantó y quedó registrado |
| **v1.5.1** | Compilar de verdad | `scripts/generar-protos.sh`, `genproto/` de los dos servicios, `main.go`, `handlers.go`, `header.html` | el código del repositorio compila; no lo hacía desde el PR #35 |

De aquí en adelante se puede entregar. Lo que sigue añade producto.

### Serie 1.6–2.x — las listas de deseos

| Ver. | Ticket | Archivos que toca | Qué pasa |
|---|---|---|---|
| **v1.6.0** | Publicar imágenes | `.github/workflows/publicar-imagenes.yml` (nuevo) | las imágenes propias llegan a GHCR |
| **v1.7.0** | Desplegar wishlistservice | `kubernetes-manifests/wishlistservice.yaml`, `redis-wishlist.yaml` (nuevo), `kustomization.yaml` | el servicio corre en el clúster, pero nadie lo ve todavía |
| **v2.0.0** | Frontend propio | `kubernetes-manifests/frontend.yaml` | **MAYOR**: la tienda ya publicada muestra el botón de guardar en lista |

La v2.0.0 es el momento en que se demuestra el CI/CD de verdad: **no se toca
AWS**. Se publica una imagen nueva, el despliegue se actualiza solo y la página
cambia en la misma URL. Eso es lo que hay que enseñar en la defensa.

### Serie 2.x–3.x — las cuentas

| Ver. | Ticket | Archivos que toca | Qué pasa |
|---|---|---|---|
| **v2.1.0** | Esquema de usuarios | `src/userservice/schema.sql` | se recupera la rama `feat/user-database-schema`, que sigue sin fusionar |
| **v2.2.0** | Servicio de usuarios | `src/userservice/` (resto), `protos/user.proto` | el servicio existe en el repositorio |
| **v2.3.0** | Desplegar userservice | `kubernetes-manifests/userservice.yaml`, `postgres.yaml` (nuevos), `kustomization.yaml` | corre en el clúster |
| **v3.0.0** | Inicio de sesión | `auth.go`, `merge.go`, las 3 plantillas, `main.go`, `handlers.go`, `header.html`, `frontend.yaml` | **MAYOR**: la misma URL permite registrarse. Restaura además el cableado que quitó la v1.5.1 (ADR 0017): es el diff más grande del proyecto |

---

## 4. Por qué ese orden y no otro

Tres reglas lo gobiernan, y conviene poder defenderlas:

**La infraestructura primero, el producto después.** La v1.0.0 es la tienda de
Google *sin modificar* sobre infraestructura nuestra. Suena raro entregar algo
que no tiene nada propio, pero es justo lo que hace legible todo lo demás: a
partir de ahí, cada cambio se ve como un cambio de aplicación y no como un
cambio de plataforma. Si se mezclaran, un fallo no diría de cuál de las dos es.

**La portabilidad antes que las funciones.** La serie 1.x no añade nada que se
vea en la pantalla. Añade que *otra persona pueda levantarlo*. Se hace antes
porque cada función nueva que se añade encima de algo no reproducible multiplica
el trabajo de arreglarlo después.

**El backend antes que la interfaz.** Dentro de cada función, primero el
servicio (v1.7.0, v2.3.0) y después el frontend que lo usa (v2.0.0, v3.0.0).
Así, cuando el botón aparece, lo que hay detrás ya se probó por separado.

---

## 5. Publicar y volver atrás

Las etiquetas se ponen **siempre sobre `main`**, y solo cuando `main` está en un
estado que de verdad levanta. Una etiqueta que no reproduce lo que promete está
mal puesta, y se corrige con una versión de parche: **las etiquetas no se mueven
ni se borran**.

```bash
# volver a cualquier punto de la historia
git checkout v1.1.0
cd infra/aws/envs/dev && terraform init && terraform apply

# ver qué cambió entre dos versiones
git diff v1.1.0 v1.2.0 --stat

# deshacer un commit ya fusionado, sin reescribir historia
git revert <sha>
```

Cada `gh release create` deja además un `.zip` descargable de esa versión. Ese
archivo es la respuesta a *«pasarle un solo archivo a alguien»*: no hace falta
clonar el repositorio para levantar la infraestructura, basta con descomprimirlo
y correr los dos comandos de `docs/infra.md`.
