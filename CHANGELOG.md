# Registro de cambios

Todas las versiones publicadas de este proyecto, la mas reciente arriba.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y la numeracion sigue [Versionado Semantico](https://semver.org/lang/es/).
La convencion concreta de este repositorio esta en [`docs/VERSIONADO.md`](docs/VERSIONADO.md).

## [Sin publicar]

### Pendiente
- `levantar.sh` y `apagar.sh`, para no depender de recordar cinco comandos.
- Borrar los diez flujos heredados de Google, que fallan en cada push.
- Flujo de GitHub Actions que corra `terraform plan` en cada PR.
- Proteger `main` contra `push --force`.
- Publicar nuestras imagenes en GHCR y apuntar los manifiestos a ellas.

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

[Sin publicar]: https://github.com/branToRep/microservices-demo/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/branToRep/microservices-demo/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/branToRep/microservices-demo/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/branToRep/microservices-demo/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/branToRep/microservices-demo/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/branToRep/microservices-demo/releases/tag/v1.0.0
