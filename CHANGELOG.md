# Registro de cambios

Todas las versiones publicadas de este proyecto, la mas reciente arriba.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y la numeracion sigue [Versionado Semantico](https://semver.org/lang/es/).
La convencion concreta de este repositorio esta en [`docs/VERSIONADO.md`](docs/VERSIONADO.md).

## [Sin publicar]

El objetivo del proyecto esta cumplido en la 2.0.0: configuracion versionada que
otra persona puede levantar sin editar nada, y un ciclo de integracion y
despliegue continuo que se demuestra en vivo. Lo que queda es producto, no
plataforma, y se construye sobre un pipeline que ya funciona.

### Pendiente
- **v2.1.0** (#62) — recuperar `src/userservice/schema.sql`.
- **v2.2.0** (#63) — el `userservice` completo. Es el unico ticket que es
  programar de verdad; el detalle heredado del plan original esta como lista de
  comprobacion en ese issue.
- **v2.3.0** (#64) — desplegarlo en el cluster, con su Postgres.
- **v3.0.0** (#65) — el inicio de sesion. Restaura ademas el cableado que quito
  la 1.5.1 (ADR 0017), asi que sera el diff mas grande del proyecto.

### Mejoras posibles, no bloqueantes
- Construir tambien las diez imagenes de Google, para no depender de su registro.
  Hoy usamos las oficiales fijadas a `v0.10.6`; anadirlas a la matriz del
  workflow es una linea. No se hace porque no hemos tocado ese codigo.
- Activar la aprobacion manual del despliegue: el trabajo ya declara
  `environment: produccion`; basta anadirle "Required reviewers" en los ajustes
  del repositorio, sin tocar el workflow.
- `apagar.sh --solo-nodos`, para bajar los nodos sin destruir el plano de
  control cuando se va a volver el mismo dia.

## [2.0.0] - 2026-09-25

**La tienda cambia, y nadie toca AWS.** Fusionas a `main`, GitHub construye la
imagen, la publica y actualiza el despliegue en el cluster. La misma URL muestra
algo distinto. Esto es lo que el proyecto existia para demostrar.

MAYOR porque cambia lo que la tienda **hace** para quien la usa: aparecen las
listas de deseos. Es la primera funcion nuestra que se ve.

### Cambiado
- `kubernetes-manifests/frontend.yaml` — la imagen pasa de la publica de Google
  (`…/microservices-demo/frontend:v0.10.6`) a `ghcr.io/brantorep/frontend:main`.
  Se declara ademas `WISHLIST_SERVICE_ADDR`: el codigo ya tenia ese valor por
  defecto, pero ponerlo en el manifiesto hace visible la dependencia.
- `.github/workflows/publicar-imagenes.yml` pasa a llamarse
  `publicar-y-desplegar.yml` y **gana el trabajo `desplegar`**.

### El pipeline completo

```
PR abierto    →  fmt · validate            (terraform-ci.yml)
merge a main  →  publicar en GHCR
                    ↓ needs: publicar
                 desplegar en EKS
```

El despliegue apunta al **SHA exacto** con `kubectl set image`, no a `:main`. Es
lo que permite saber que version corre y volver atras apuntando a otro SHA. Las
etiquetas `:main` de los manifiestos son el suelo para un despliegue desde cero.

### Dos decisiones que lleva dentro

**No falla cuando el laboratorio esta cerrado.** Las credenciales del lab caducan
con la sesion. El trabajo comprueba que *todavia sirven* —no que existan: un
secreto viejo existe igual— y si no, se **salta** con un aviso. Un despliegue en
rojo por credenciales caducadas seria un pipeline mintiendo sobre el codigo, y
un CI siempre en rojo se aprende a ignorar (el problema de la v1.3.1).

**La puerta manual esta preparada, no activada.** El trabajo lleva
`environment: produccion`. Hoy ese entorno no tiene reglas y no bloquea. Si quien
administra el repositorio le anade "Required reviewers" en
Settings → Environments, el despliegue pasara a esperar aprobacion **sin tocar
una linea del workflow**. Se deja asi porque configurar entornos pide permisos
de administracion, que este equipo no tiene sobre el fork.

### Corregido
- `scripts/aws/sincronizar-credenciales.sh` — no tenia **shebang** y estaba
  versionado con modo `100644`, sin bit de ejecucion. Es decir,
  `./scripts/aws/sincronizar-credenciales.sh` fallaba con "permission denied" en
  cualquier clon, y ese es el comando que documentan este workflow,
  `terraform-ci.yml` y `docs/IMAGENES-GHCR.md`. Los otros tres scripts del
  proyecto si estaban en `100755`. Lo encontro el primer intento de usarlo para
  desplegar.

### Revertir
Si el `rollout` no cuaja, el propio trabajo hace `kubectl rollout undo`.
Kubernetes mantiene los pods viejos hasta que los nuevos esten listos, asi que la
tienda no se cae durante un despliegue fallido.

## [1.7.0] - 2026-09-25

El `wishlistservice` empieza a correr en el cluster. **Todavia no se ve nada** en
la tienda: el frontend desplegado sigue siendo la imagen publica de Google, que
no sabe que existen las listas. Eso llega en la v2.0.0.

Desplegar el servicio antes que su interfaz es deliberado: se puede comprobar
aislado —que arranca, que habla con su Redis, que su sonda de salud responde—
sin que un fallo se confunda con un fallo del frontend.

### Cambiado
- `kubernetes-manifests/kustomization.yaml` — **anade `wishlistservice.yaml`.**
  Ese manifiesto existia desde el PR #31 pero nunca estuvo en esta lista, asi que
  `kubectl apply -k` no lo aplicaba nunca: el archivo estaba en el repositorio y
  el servicio no en el cluster. Nadie lo noto porque la tienda funcionaba — sin
  listas de deseos, pero funcionaba.
- `kubernetes-manifests/wishlistservice.yaml` — la imagen pasa de
  `boutique/wishlistservice:local` (construida a mano, solo existia en el Docker
  de un portatil) a `ghcr.io/brantorep/wishlistservice:main`, que publica el CI.
  `imagePullPolicy` pasa a `Always`.

### Sobre la etiqueta `:main` en el manifiesto
Va `:main` y no un SHA a proposito. El manifiesto es el **suelo**: lo que se
despliega en un `kubectl apply -k` desde cero. El despliegue continuo de la
v2.0.0 apunta al SHA exacto con `kubectl set image`, que es lo que permite saber
que version corre y volver atras.

El precio es que un `apply -k` posterior a un despliegue devuelve el servicio a
`:main`. Es aceptable mientras el entorno se destruya cada sesion; en un cluster
permanente habria que fijar la imagen desde el CI con el transformador `images`
de kustomize.

### Requisito externo
Los paquetes de GHCR nacen **privados**. Si `wishlistservice` sigue privado, los
nodos no pueden descargarlo y el pod queda en `ImagePullBackOff` con un 401 que
parece un problema de red. Hay que hacerlo publico una vez, y solo puede el dueno
del paquete (`docs/IMAGENES-GHCR.md`).

## [1.6.0] - 2026-09-25

**Primera version en la que GitHub *hace* algo.** Hasta ahora el CI opinaba
—revisaba formato, validaba, comentaba planes— pero construir seguia siendo cosa
de un portatil. Desde aqui, las imagenes salen del runner.

### Anadido
- `.github/workflows/publicar-imagenes.yml` — construye y publica
  `frontend` y `wishlistservice` en GHCR en cada push a `main` que toque
  `src/frontend/`, `src/wishlistservice/` o `protos/`.
- `docs/IMAGENES-GHCR.md` — que imagenes son nuestras, como se etiquetan y el
  unico paso de configuracion que hay que hacer una vez.

### Decisiones que lleva dentro

**Publica, no despliega.** El despliegue a EKS es la v2.0.0. Publicar es seguro
y repetible; desplegar cambia lo que la gente ve. Van en versiones distintas.

**Etiqueta por SHA del commit**, no `:latest`. `ghcr.io/…/frontend:a8a7ede` dice
exactamente que codigo corre, y volver atras es apuntar a otro SHA. Se publica
tambien `:main` por comodidad, pero los despliegues usan el SHA: con `:latest`
nadie sabe que version esta viva.

**Solo `linux/amd64`.** El runner es amd64 y los nodos `t3.medium` tambien, asi
que no hace falta emulacion. Construir en un Mac (arm64) daba imagenes que
arrancan en local y fallan en el cluster con `exec format error`, un mensaje que
no menciona la arquitectura. Es una razon de peso para que construya el CI.

**Sin secretos.** El `GITHUB_TOKEN` de cada ejecucion basta con
`permissions: packages: write`. No hay nada que rotar, al contrario que las
credenciales de AWS.

### Corregido
- `src/frontend/main.go` — usaba `otelgrpc.UnaryClientInterceptor` y
  `StreamClientInterceptor`, **eliminadas** de la libreria hace varias versiones
  y sustituidas por un unico `StatsHandler`. El `go.mod` de este fork ya venia
  con `otelgrpc v0.70.0` (por los PR #3327 y #3445 de Google), y el `main.go`
  que entro en el PR #35 estaba escrito contra la API anterior. Mismo patron que
  el cableado de cuentas: ese PR reemplazo `main.go` entero por una version hecha
  para otro conjunto de dependencias.

  Lo encontro el primer intento de construir la imagen. La v1.5.1 habia dejado el
  frontend compilando **contra las dependencias de la maquina donde se probo**;
  aqui se compila contra las que declara el `go.mod`, que es lo que vale.

### Quitado del plan
- La tercera imagen prevista, `loadgenerator`, no entra:
  `src/loadgenerator/locustfile.py` en este repositorio es el de Google **sin
  modificar** y no genera trafico de listas. Publicar una imagen identica a la
  publica no aporta nada.

### Pendiente de un paso manual
Los paquetes de GHCR nacen **privados**, y una imagen privada no la puede
descargar el cluster: los nodos no tienen credenciales de GitHub y el pod queda
en `ImagePullBackOff` con un 401 que parece un problema de red. Hay que hacerlas
publicas una vez, y solo puede el dueno del paquete. El procedimiento y la
alternativa (`imagePullSecret`) estan en `docs/IMAGENES-GHCR.md`.

## [1.5.1] - 2026-09-25

Esta version no anade funciones: **hace que el codigo compile**. Los dos defectos
que arregla llevaban meses en `main`, revisados y fusionados, sin que nadie los
viera — porque hasta ahora nada habia construido nuestro frontend. La tienda
desplegada usa la imagen publica de Google.

### Anadido
- `scripts/generar-protos.sh` — genera el codigo Go de `protos/wishlist.proto`
  corriendo `protoc` y los plugins **dentro de un contenedor**: solo hace falta
  Docker, y las versiones del generador estan fijadas.
- `src/frontend/genproto/wishlist.pb.go`, `wishlist_grpc.pb.go`
- `src/wishlistservice/genproto/wishlist.pb.go`, `wishlist_grpc.pb.go`
- ADR 0016 — por que el codigo generado se versiona.
- ADR 0017 — por que el frontend va sin cuentas hasta la v3.0.0.

### Corregido
- **El codigo gRPC de wishlist no estaba en el repositorio** y ademas estaba en
  el `.gitignore`. Los dos servicios importan un paquete `genproto` que no
  existia; al frontend le faltaban doce tipos. Habia funcionado en local porque
  las maquinas donde se escribio tenian ese directorio generado sin versionar.
- **El frontend no compilaba desde el PR #35.** Ese PR metio el cableado de
  cuentas de usuario sin la implementacion: ocho rutas, dos campos del struct, el
  middleware `withUser` y cuatro llamadas a funciones que **nunca han existido en
  la historia del repositorio** (`auth.go` y `merge.go` tienen cero commits). Se
  quita el cableado; vuelve completo en la v3.0.0 (ADR 0017).

### Cambiado
- `.gitignore` — deja de ignorar `src/wishlistservice/genproto/`.
- `src/frontend/main.go`, `handlers.go`, `templates/header.html` — 37 lineas
  menos: fuera las rutas de cuentas, el menu de perfil y el boton "Entrar".

### Lo que esto ensena

Van cuatro mecanismos y cuatro defectos reales, cada uno encontrado en su primer
uso:

| Mecanismo | Que encontro |
|---|---|
| CI (1.4.0) | cinco `.tf` mal formateados desde la 1.0.0 |
| Proteccion de `main` (1.4.1) | un check requerido que bloqueaba los PR que no lo disparaban |
| Prueba en clon limpio (1.5.0) | un fallo de lectura y un mensaje de error que mentia |
| Compilar de verdad (1.5.1) | el frontend roto desde el PR #35 |

El ultimo es el mas contundente: codigo en `main`, revisado y fusionado, que no
compilaba. Es el argumento de por que el despliegue continuo importa — no basta
con versionar el codigo, hay que construirlo.

## [1.5.0] - 2026-09-25

**Cierra la serie 1.x.** A partir de esta version, otra persona clona el
repositorio y lo levanta sin editar ningun archivo del proyecto. Es el objetivo
que se planteo al empezar, y aqui queda comprobado en lugar de supuesto.

### Anadido
- `docs/PRUEBA-CLON-LIMPIO.md` — el procedimiento de la prueba y su resultado.
- `docs/proteccion-main.json` — la configuracion de proteccion de `main` como
  archivo, para reaplicarla en cualquier sistema sin pelear con comillas.

### Corregido
- `scripts/aws/levantar.sh` y `scripts/aws/apagar.sh` — leian el nombre del
  bucket con un `sed` que imprimia **todas** las coincidencias. Un `backend.hcl`
  con la linea `bucket` duplicada metia un salto de linea dentro de la variable y
  el script construia la ruta `s3://bucket\nbucket/`. Y lo peor era el mensaje:
  culpaba a las credenciales del laboratorio, mandando a buscar al sitio
  equivocado. Ahora cuentan las coincidencias antes de leerlas y dicen que pasa.
- `docs/PROTECCION-RAMAS.md` — decia "documentada, no aplicada todavia". Ya esta
  aplicada; se anota como, quien y el detalle del `name already protected`.
- `.github/workflows/terraform-ci.yml` — se le quita el filtro `paths`. El flujo
  es un check **requerido** en la proteccion de `main`, y un check requerido que
  no corre no queda "no aplicable": queda **pendiente**, y bloquea la fusion para
  siempre. Con `paths: infra/**`, cualquier PR que solo tocara documentacion o
  scripts era imposible de fusionar, y el mensaje de GitHub ("the base branch
  policy prohibits the merge") no dice por que. Lo descubrio este mismo PR al
  intentar fusionarse. La regla que queda: **un check requerido corre en todos
  los PR.**

### La prueba

Un clon nuevo, un bucket de estado propio, y un solo archivo escrito a mano
(`backend.hcl`, dos lineas). Los cinco puntos pasaron. El que importa es el
tercero: **`git status --short` salio completamente vacio** — ningun `.tf`
modificado. Si hubiera hecho falta editar codigo para levantarlo, la etiqueta
dejaria de significar lo que dice y todo el versionado seria decorativo.

La prueba encontro los dos defectos de arriba, ninguno visible desde la carpeta
de trabajo original. Es el mismo patron de la 1.4.0, donde el CI nuevo encontro
cinco archivos mal formateados en su propio PR: cada mecanismo que se anade
descubre un defecto real en su primer uso.

De paso quedo confirmado que **el versionado del bucket de estado si esta
activo** — la SCP del laboratorio no lo denego. Se vio al intentar borrar el
bucket de la prueba: `aws s3 rm --recursive` no basta, hay que borrar todas las
versiones.

## [1.4.1] - 2026-09-25

### Anadido
- `docs/PROTECCION-RAMAS.md` — la configuracion de proteccion de `main`, con el
  comando que la aplica y el motivo de cada ajuste.

La proteccion en si no es un archivo del repositorio, es configuracion de
GitHub. Se documenta aqui porque de otro modo nadie sabria que existe, ni podria
reproducirla en otro repositorio.

Lo que impide, en orden de importancia:

- **`push --force` sobre `main`.** Es lo unico verdaderamente irreversible de
  Git: reescribe commits que otros ya tienen. Borrar una rama fusionada, en
  cambio, no destruye nada — sus commits siguen en la historia de `main`.
- **Borrar `main`.**
- **Fusionar con el CI en rojo**, exigiendo el trabajo "Formato y sintaxis", que
  es el que no depende de credenciales de AWS.
- **Fusionar contra un `main` desactualizado** (`strict: true`), que es lo que
  arrastraba trabajo ajeno a los PR.

No exige aprobacion de otra persona (`required_approving_review_count: 0`): si
exige PR, pero no que alguien lo apruebe. Somos dos con horarios distintos y un
PR esperando dias no ensena nada sobre CI/CD. Subirlo a 1 no requiere ningun
otro cambio.

**La proteccion queda documentada pero todavia no aplicada.** El fork pertenece
a `branToRep` y el resto del equipo entra como colaborador con permiso `push`,
que alcanza para ramas y PR pero no para configurar la rama por defecto: el
comando devuelve 404 (GitHub responde 404 en vez de 403 para no revelar si el
recurso existe). El repositorio es publico, asi que no es cuestion de plan.
Puede aplicarla `branToRep`, o quien sea subido a Admin. El documento explica
que riesgo queda mientras no este.

## [1.4.0] - 2026-09-25

### Anadido
- `.github/workflows/terraform-ci.yml` — revisa la infraestructura en cada PR
  que toque `infra/`. Primer flujo propio del proyecto; la carpeta estaba vacia
  desde la 1.3.1.

Son **dos trabajos**, y la division es lo importante:

| Trabajo | Que hace | Necesita AWS | Bloquea la fusion |
|---|---|---|---|
| Formato y sintaxis | `fmt -check`, `init -backend=false`, `validate` | no | **si** |
| Plan contra AWS | `plan` y lo comenta en el PR | si | no |

El primero corre `init -backend=false`, que prepara modulos y proveedor sin
conectarse a S3. Por eso valida sin credenciales y nunca falla por razones
ajenas al codigo.

El segundo solo arranca si existen los secretos y la variable `TF_BUCKET`, y
lleva `continue-on-error`. El motivo es que las credenciales del laboratorio
caducan cada sesion: si el PR se bloqueara por no haberlas sincronizado hoy, el
CI estaria en rojo por algo que no es el codigo, y un CI siempre en rojo se
aprende a ignorar — que es justo el problema que resolvio la 1.3.1.

Detalles que no se ven pero importan:

- `plan -lock=false` — el CI solo lee. Sin esa bandera, un plan puede dejar el
  candado puesto en S3 y bloquear a quien este aplicando desde su maquina.
- El comentario del plan lleva una marca oculta y se **reescribe** en cada
  commit, en vez de apilar un comentario por corrida.
- `concurrency` cancela la corrida anterior del mismo PR.

### Corregido
- `scripts/aws/sincronizar-credenciales.sh` — el mensaje final decia
  "credenciales configudradasproceso".
- Formato canonico (`terraform fmt`) en cinco archivos de `infra/aws/modules/`.
  Llevaban mal formateados desde la 1.0.0 y nadie lo habia notado: el flujo
  nuevo lo detecto en su propio PR, que es exactamente para lo que esta.

## [1.3.1] - 2026-09-25

### Quitado
- Los diez flujos de GitHub Actions heredados del repositorio de Google:
  `ci-main`, `ci-pr`, `cleanup`, `deploy-pr`, `helm-chart-ci`,
  `kubevious-manifests-ci`, `kustomize-build-ci`, `make-release`,
  `terraform-validate-ci` y el `README.md` de esa carpeta.

Estaban escritos para la infraestructura de Google —su proyecto de GCP, sus
secretos, su registro de imagenes— y fallaban en cada push desde el primer dia.
Un CI permanentemente en rojo deja de avisar de nada: cuando todo falla siempre,
nadie mira si algo empezo a fallar. Se van juntos porque comparten una unica
razon, y hay que quitarlos antes de anadir el nuestro para que el nuestro se
distinga.

Siguen en la historia: `git show v1.3.0:.github/workflows/ci-main.yaml` los
recupera si alguna vez hace falta consultar como los tenia Google.

## [1.3.0] - 2026-09-25

### Anadido
- `scripts/aws/apagar.sh` — apaga y destruye en el orden que no deja residuos.

El aporte del script no es encadenar comandos, es el **orden**. Terraform
destruye lo que Terraform creo, y nada mas; Kubernetes y EKS crean cosas por su
cuenta dentro de la VPC. Si los nodos mueren con los pods encima, esas cosas se
quedan bloqueando el borrado de las subredes con `DependencyViolation`, Terraform
reintenta veinte minutos y se rinde, y el error nunca menciona la causa.

Son tres residuos, con tres duenos distintos:

| Lo que queda | Quien lo creo |
|---|---|
| grupo de seguridad `k8s-elb-...` | el controlador de Kubernetes, para un Service de tipo LoadBalancer |
| interfaz de red `aws-K8S-i-...` | el CNI, para dar IPs a los pods |
| grupo `eks-cluster-sg-...` | EKS mismo, al crear el cluster |

Quitar los pods **antes** de tocar AWS evita casi todo: si se van primero, el CNI
devuelve sus interfaces solo. El script hace eso, espera, y si el `destroy` falla
igual, barre los residuos y reintenta hasta tres veces.

Tambien se niega a borrar nada si `kubectl` apunta a otro cluster, para no
destruir por error algo que no es este proyecto.

## [1.2.0] - 2026-09-25

### Anadido
- `scripts/aws/levantar.sh` — levanta todo con un comando. Antes eran cinco
  pasos en dos directorios distintos, y equivocarse de directorio o de contexto
  de kubectl daba errores que no se parecian a su causa.

El script no solo encadena los comandos; incorpora las dos comprobaciones que
mas tiempo costaron durante el desarrollo:

- **Que las credenciales sirvan de verdad.** Hace `aws s3 ls` contra el bucket
  del estado, no `sts get-caller-identity`: ese ultimo responde igual con
  credenciales ya canceladas por la SCP del laboratorio, asi que no prueba nada.
- **Que kubectl apunte al cluster de AWS.** Compara el contexto con el nombre
  del cluster y se detiene si no coinciden. Once pods corriendo en el Kubernetes
  de Docker Desktop parecen exito y no lo son.

Ademas lee el bucket desde `backend.hcl` y explica como crearlo si falta, espera
a que los despliegues esten disponibles, y sondea la URL hasta recibir un 200
—los pods pueden estar listos mientras el balanceador sigue marcando los nodos
`OutOfService` durante un minuto mas.

## [1.1.1] - 2026-09-25

### Cambiado
- `infra/aws/envs/dev/versions.tf` — `required_version` pasa de `>= 1.10` a
  `~> 1.10`. Antes, cualquier version futura valia, incluida Terraform 2.x.
- `infra/aws/envs/dev/variables.tf` — `version_kubernetes` deja de ser `null` y
  se fija en **1.34**. Con `null`, EKS elegia "la mas reciente de hoy", asi que
  la misma etiqueta de Git daba un cluster distinto seis meses despues. El
  laboratorio admite de 1.31 a 1.36; 1.34 esta dos por detras de la punta,
  donde los addons ya son estables y falta mucho para el fin de soporte.

### Corregido
- `docs/infra.md` y este archivo decian que el modulo `cluster` tiene 5
  recursos. Son **6**: se paso por alto
  `aws_vpc_security_group_ingress_rule.nodeports_desde_elb`, que entro con el
  balanceador. El total de los tres modulos es **21**, no 20.
- `docs/infra.md` — la seccion del backend describia el bucket escrito a fuego,
  que dejo de ser verdad en la 1.1.0, y la del estado hablaba de un
  `errored.tfstate` que ya no existe. En su lugar queda documentados los tres
  residuos que `terraform destroy` no se lleva (el grupo de seguridad del ELB de
  Kubernetes, las interfaces del CNI y el grupo de seguridad de EKS).

## [1.1.0] - 2026-09-25

### Cambiado
- `infra/aws/envs/dev/backend.tf` — se le quitan `bucket` y `region`. El estado
  sigue en S3, pero el nombre del bucket se pasa al `init`:
  `terraform init -backend-config=backend.hcl`.

### Anadido
- `infra/aws/envs/dev/backend.hcl.ejemplo` — la plantilla que se copia a
  `backend.hcl` y se edita. Esta si se versiona; `backend.hcl` no.
- `.gitignore` — ignora `infra/aws/envs/dev/backend.hcl`.

### Por que
Los nombres de bucket de S3 son unicos en todo AWS. Mientras el nuestro estuvo
escrito en `backend.tf`, nadie mas podia correr el proyecto sin editar codigo —
y al editarlo dejaba de estar ejecutando la version que dice la etiqueta.
**Primera version que otra persona puede levantar tal cual.**

## [1.0.2] - 2026-09-24

### Anadido
- `docs/infra.md` — mapa de la infraestructura: que hace cada archivo de
  `infra/`, como fluyen los datos entre los tres modulos, que se versiona y que
  no, y desde que directorio se corre cada comando.

## [1.0.1] - 2026-09-24

### Anadido
- `CHANGELOG.md` — este archivo.
- `docs/VERSIONADO.md` — la convencion: una version por ticket, que numero sube
  en cada caso, el camino completo de la 1.0.0 a la 3.0.0 y como se publica.

## [1.0.0] - 2026-09-23

Primera version que se levanta entera en AWS. Es la tienda **de Google, sin
modificar**, corriendo sobre infraestructura **nuestra**, declarada por completo
en Terraform. Es a proposito: fija la linea base de infraestructura antes de
tocar el producto, para que lo que venga despues se vea como un cambio de
aplicacion y no como un cambio de plataforma.

### Añadido

**Infraestructura en AWS (Terraform)**
- `infra/aws/modules/red/` — VPC 10.0.0.0/16, dos zonas de disponibilidad,
  subredes publicas y privadas, internet gateway y tablas de ruteo (12 recursos).
- `infra/aws/modules/cluster/` — cluster de EKS y grupo de nodos administrado
  con capacidad SPOT, addons `vpc-cni`, `coredns` y `kube-proxy`, y la regla
  que deja entrar el rango de NodePorts desde la VPC (6 recursos).
- `infra/aws/modules/balanceador/` — ELB clasico con su grupo de seguridad y el
  enganche al grupo de autoescalado de los nodos (3 recursos).
- `infra/aws/envs/dev/` — el entorno que compone los tres modulos, con el estado
  en S3 (`use_lockfile = true`, sin DynamoDB) y las salidas que hacen falta para
  operar: `comando_kubeconfig` y `url_tienda`.
- `infra/aws/bootstrap/crear-bucket-estado.sh` — crea el bucket del estado con
  la CLI, porque el laboratorio no deja hacerlo con Terraform (ver ADR 0013).
- `scripts/aws/sincronizar-credenciales.sh` — sube al repositorio las tres
  credenciales del laboratorio como secretos de GitHub.

**Decisiones registradas**
- ADR 0013 — el bucket del estado se crea con la CLI, no con Terraform.
- ADR 0014 — no hay NAT gateway; los nodos van en subredes publicas.
- ADR 0015 — no se crean roles de IAM propios; se reutiliza `LabRole`.

**Servicio de listas de deseos (codigo, todavia sin desplegar)**
- `protos/wishlist.proto` y `protos/user.proto`.
- `src/wishlistservice/` completo, con su cliente de Redis y su almacenamiento.
- Cliente gRPC, manejadores y plantillas de listas en el frontend.
- `kubernetes-manifests/wishlistservice.yaml`.

### Cambiado
- `kubernetes-manifests/frontend.yaml` — el Service pasa de `LoadBalancer` a
  `NodePort` con el puerto fijo 30080. El controlador de nube del laboratorio
  no puede administrar ELBs, asi que el balanceador lo declara Terraform y
  apunta a ese puerto fijo.
- Los nueve manifiestos de Google pasan a usar imagenes fijadas del registro
  publico, en vez de los nombres sueltos que espera skaffold.

### Notas de esta version
- El frontend que se despliega es **la imagen publica de Google**. Las listas de
  deseos y las cuentas estan en el repositorio pero no en el cluster todavia:
  eso llega en la 2.0.0.
- `src/userservice/` aun no existe en el repositorio.
- El nombre del bucket del estado esta escrito a fuego en `backend.tf`. En otra
  computadora hay que cambiarlo a mano; se arregla en la 1.1.0.

[Sin publicar]: https://github.com/branToRep/microservices-demo/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/branToRep/microservices-demo/compare/v1.7.0...v2.0.0
[1.7.0]: https://github.com/branToRep/microservices-demo/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/branToRep/microservices-demo/compare/v1.5.1...v1.6.0
[1.5.1]: https://github.com/branToRep/microservices-demo/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/branToRep/microservices-demo/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/branToRep/microservices-demo/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/branToRep/microservices-demo/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/branToRep/microservices-demo/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/branToRep/microservices-demo/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/branToRep/microservices-demo/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/branToRep/microservices-demo/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/branToRep/microservices-demo/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/branToRep/microservices-demo/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/branToRep/microservices-demo/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/branToRep/microservices-demo/releases/tag/v1.0.0
