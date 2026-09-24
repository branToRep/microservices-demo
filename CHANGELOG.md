# Registro de cambios

Todas las versiones publicadas de este proyecto, la mas reciente arriba.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y la numeracion sigue [Versionado Semantico](https://semver.org/lang/es/).
La convencion concreta de este repositorio esta en [`docs/VERSIONADO.md`](docs/VERSIONADO.md).

## [Sin publicar]

### Pendiente
- Publicar nuestras imagenes en GHCR y apuntar los manifiestos a ellas.
- Configuracion parcial del backend (`backend.hcl`) para que el bucket del
  estado no este escrito a fuego en el codigo.
- Flujo de GitHub Actions que corra `terraform plan` en cada PR.

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
  que deja entrar el rango de NodePorts desde la VPC (5 recursos).
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

[Sin publicar]: https://github.com/branToRep/microservices-demo/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/branToRep/microservices-demo/releases/tag/v1.0.0
