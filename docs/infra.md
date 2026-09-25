# Mapa de la infraestructura

Qué hace cada archivo de `infra/`, por qué existe y qué se rompe si falta.

Son 15 archivos `.tf`, dos de configuración y un script — 645 líneas en total. Se ven muchos,
pero la estructura es sencilla: hay **un entorno** que no declara casi nada y
**tres módulos** que hacen el trabajo. El entorno solo los cablea entre sí.

---

## 1. El mapa de un vistazo

```
infra/aws/
│
├── bootstrap/
│   └── crear-bucket-estado.sh      se corre UNA VEZ, antes que nada
│
├── envs/dev/                       EL ENTORNO — aquí se corre terraform
│   ├── versions.tf                 qué versión de Terraform y del proveedor
│   ├── providers.tf                cómo hablar con AWS + etiquetas automáticas
│   ├── backend.tf                  dónde vive el estado (sin el nombre del bucket)
│   ├── backend.hcl.ejemplo         plantilla: el bucket, que cambia por máquina
│   ├── variables.tf                las perillas que se pueden girar
│   ├── terraform.tfvars            cómo están giradas HOY
│   ├── main.tf                     cablea los tres módulos
│   └── outputs.tf                  lo que escupe al terminar
│
└── modules/                        LAS PIEZAS — no se corren solas
    ├── red/                        VPC, subredes, rutas          (12 recursos)
    ├── cluster/                    EKS, nodos, addons            ( 6 recursos)
    └── balanceador/                ELB y su grupo de seguridad   ( 3 recursos)
```

**Módulo** = una carpeta de Terraform reutilizable. No se ejecuta sola: recibe
valores por sus `variables.tf`, crea cosas en su `main.tf`, y devuelve datos por
su `outputs.tf`. Es una función, con argumentos y valor de retorno.

**Entorno** = la carpeta donde sí se corre `terraform apply`. Aquí solo hay una
(`dev`), pero el patrón permite añadir `prod/` al lado reutilizando los mismos
módulos con otros valores.

---

## 2. Cómo fluye la información

Este es el corazón del diseño. Nadie escribe un ID a mano en ningún lado: cada
módulo pide lo que necesita y el de antes se lo da. Por eso Terraform sabe el
orden en que tiene que construir, y por eso destruye en orden inverso.

```
                    variables.tf + terraform.tfvars
                                 │
                                 ▼
  ┌──────────────────────────  main.tf  ──────────────────────────┐
  │                                                               │
  │   module "red"                                                │
  │       ↓ devuelve: vpc_id, subredes_publicas, subredes_privadas│
  │                                                               │
  │   module "cluster"  ← recibe las subredes de la red           │
  │       ↓ devuelve: nombre, endpoint, asg_nodos                 │
  │                                                               │
  │   module "balanceador"  ← recibe vpc_id + subredes + asg_nodos│
  │       ↓ devuelve: dns                                         │
  │                                                               │
  └───────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                            outputs.tf
                     (url_tienda, comando_kubeconfig)
```

Si intentaras crear el clúster antes que la red, Terraform se negaría: no puede
resolver `module.red.subredes_publicas` si la red no existe todavía. **El orden
no está escrito en ningún lado — sale solo de las dependencias.**

---

## 3. El entorno, archivo por archivo

### `envs/dev/versions.tf` — 10 líneas

Fija las versiones. Nada más.

```hcl
required_version = "~> 1.10"
aws = { version = "~> 5.70" }
```

`~> 1.10` significa «de 1.10 en adelante, pero por debajo de 2.0». El límite
inferior no es capricho: `use_lockfile` en el backend de S3 (el bloqueo del
estado sin DynamoDB) apareció en esa versión, y con Terraform 1.9 el `backend.tf`
no funciona. El superior evita que dentro de dos años alguien corra Terraform 2.x
y obtenga algo que no se parece a lo que promete la etiqueta.

### `envs/dev/providers.tf` — 13 líneas

Configura el proveedor de AWS y, lo importante, pone `default_tags`:

```hcl
default_tags {
  tags = {
    Proyecto      = var.proyecto
    Entorno       = "dev"
    GestionadoPor = "terraform"
  }
}
```

Cada recurso nace etiquetado sin que nadie se acuerde de hacerlo. Sirve para
dos cosas: preguntarle a Cost Explorer cuánto costó *este* proyecto, y
distinguir de un vistazo lo que es nuestro de lo que dejó un experimento.

### `envs/dev/backend.tf` — 12 líneas

Dónde vive el archivo de estado. **Este es el archivo más importante de todos.**

```hcl
backend "s3" {
  key          = "dev/terraform.tfstate"
  encrypt      = true
  use_lockfile = true
}
```

El *estado* es el inventario que Terraform lleva de lo que ya construyó. Sin él
no sabe que la VPC existe y trataría de crear otra. Vive en S3 y no en el disco
para que dos personas no se pisen: `use_lockfile` pone un candado en el bucket
mientras uno de los dos está aplicando.

Fíjate en lo que **no** aparece: el nombre del bucket ni la región. Los nombres
de bucket son únicos en todo AWS, así que tenerlos aquí obligaba a cualquier otra
persona a editar código antes de poder correr el proyecto — y en cuanto edita
código, ya no está ejecutando la versión que dice la etiqueta. Se pasan al `init`
desde un archivo que no se versiona:

```bash
cp backend.hcl.ejemplo backend.hcl     # y editas el nombre
terraform init -backend-config=backend.hcl
```

Terraform llama a esto **configuración parcial**: el archivo declara *que* el
estado va en S3, y lo que cambia de una máquina a otra se pasa por fuera.
`backend.hcl.ejemplo` es la plantilla y sí se versiona; `backend.hcl` es el de
cada quien y está en el `.gitignore`.

El precio es que `terraform init` a secas ya no funciona: sin el
`-backend-config`, Terraform pregunta el nombre del bucket por teclado. Eso lo
resuelve `levantar.sh`.

### `envs/dev/variables.tf` — 60 líneas

Las siete perillas del proyecto. Ninguna crea nada; solo declaran qué se puede
ajustar y con qué valor por defecto.

| Variable | Por defecto | Para qué |
|---|---|---|
| `proyecto` | `boutique` | prefijo del nombre de todos los recursos |
| `region` | `us-east-1` | el laboratorio solo permite esta y `us-west-2` |
| `cidr_vpc` | `10.0.0.0/16` | rango de la red privada |
| `crear_nat` | `false` | el interruptor de los ~33 USD/mes (ver ADR 0014) |
| `version_kubernetes` | `1.34` | fijada: con `null`, EKS elegiría otra en seis meses |
| `tipo_instancia` | `t3.medium` | el laboratorio no pasa de `large` |
| `numero_nodos` | `2` | poner a `0` apaga sin destruir |
| `nodeport_frontend` | `30080` | **tiene que coincidir con el manifiesto** |

Las dos últimas filas son las que más se tocan en el día a día, y la última es
la que más duele si se desincroniza: si cambias el `nodePort` en
`kubernetes-manifests/frontend.yaml` y no aquí, el balanceador comprueba un
puerto donde no escucha nadie, los nodos salen `OutOfService` y la tienda
devuelve `000`. El síntoma no menciona el puerto por ninguna parte.

Sobre `version_kubernetes`: el laboratorio admite de 1.31 a 1.36, y está fijada
en **1.34**. No la más nueva, porque los addons tardan en estabilizarse en ella;
no la más vieja, porque se acerca al fin de soporte. Dos por detrás de la punta
es el punto cómodo.

### `envs/dev/terraform.tfvars` — 4 líneas

Cómo están giradas las perillas ahora mismo. Es el único archivo que un
compañero tocaría para cambiar el despliegue sin tocar código.

```hcl
proyecto  = "boutique"
region    = "us-east-1"
crear_nat = false
```

Se versiona **a propósito**, contra lo que dicta la costumbre. La línea 19 del
`.gitignore` que venía del repositorio de Google ignora todos los `*.tfvars`,
y lo desactivamos con una excepción explícita. El motivo: aquí no hay secretos,
solo configuración, y sin este archivo nadie puede reproducir el despliegue.

### `envs/dev/main.tf` — 48 líneas

No declara ni un solo recurso. Solo llama a los tres módulos y les pasa valores.
La línea que más piensa de todo el proyecto es esta:

```hcl
subredes_nodos = var.crear_nat ? module.red.subredes_privadas : module.red.subredes_publicas
```

Si hay NAT, los nodos van en subredes privadas (seguro, cuesta dinero). Si no,
en públicas con IP pública (barato, menos seguro). Un solo `bool` cambia la
topología entera de la red.

### `envs/dev/outputs.tf` — 35 líneas

Lo que imprime al terminar. Dos de los ocho son los que se usan de verdad:

```hcl
output "comando_kubeconfig" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.cluster.nombre}"
}

output "url_tienda" {
  value = "http://${module.balanceador.dns}"
}
```

Ese primero es un detalle que ahorra mucho tiempo: en vez de decirte el nombre
del clúster para que armes el comando, te da el comando ya armado.

---

## 4. Los módulos, archivo por archivo

### `modules/red/` — la red (12 recursos)

| Archivo | Líneas | Contenido |
|---|---|---|
| `variables.tf` | 3 | `proyecto`, `cidr_vpc`, `crear_nat` |
| `main.tf` | 112 | todo el trabajo |
| `outputs.tf` | 11 | `vpc_id`, `subredes_publicas`, `subredes_privadas` |

Lo que crea `main.tf`:

- **1 VPC** con `enable_dns_hostnames = true` — EKS no funciona sin eso.
- **1 internet gateway** y su tabla de ruta con la salida `0.0.0.0/0`.
- **2 subredes públicas**, una por zona de disponibilidad. Son dos y no una
  porque **EKS exige dos zonas**: con una sola, la creación del clúster falla.
- **2 subredes privadas**, que se crean siempre aunque no haya NAT, porque una
  subred vacía no cuesta nada.
- **NAT gateway + IP elástica**, pero solo si `crear_nat = true`. El patrón es
  `count = var.crear_nat ? 1 : 0`: la forma de Terraform de decir «este recurso
  existe condicionalmente».

Dos detalles que no se ven pero importan:

```hcl
cidr_block = cidrsubnet(var.cidr_vpc, 8, count.index)        # públicas:  10.0.0.x, 10.0.1.x
cidr_block = cidrsubnet(var.cidr_vpc, 8, count.index + 10)   # privadas:  10.0.10.x, 10.0.11.x
```

`cidrsubnet` parte el rango grande en pedazos sin que nadie calcule máscaras a
mano. El `+ 10` deja un hueco entre los dos grupos para poder crecer.

```hcl
tags = { "kubernetes.io/role/elb" = "1" }
```

Esa etiqueta **no es decorativa**. Es como el controlador de balanceadores de
Kubernetes descubre en qué subredes puede crear un ELB. Sin ella, un Service de
tipo `LoadBalancer` se queda en `<pending>` para siempre y el error no dice
por qué.

### `modules/cluster/` — EKS (6 recursos)

| Archivo | Líneas | Contenido |
|---|---|---|
| `variables.tf` | 11 | las subredes, el tipo y número de nodos, el CIDR |
| `main.tf` | 124 | el clúster, los nodos, tres addons y una regla de firewall |
| `outputs.tf` | 17 | `nombre`, `endpoint`, `grupo_seguridad_cluster`, `asg_nodos` |

Lo que crea:

- **`aws_eks_cluster`** — el plano de control. Con `enabled_cluster_log_types`
  para poder investigar cuando algo no arranca, y `access_config` en modo
  `API_AND_CONFIG_MAP` para poder añadir compañeros después.
- **`aws_eks_node_group`** — dos máquinas `t3.medium` en modo **SPOT** (≈70 %
  más baratas; AWS puede retirarlas con dos minutos de aviso, que para
  servicios sin estado es casi gratis).
- **Tres addons**: `vpc-cni`, `coredns`, `kube-proxy`.
- **Una regla de grupo de seguridad** que abre el rango 30000-32767.

Tres decisiones que vale la pena entender:

```hcl
data "aws_iam_role" "lab" { name = "LabRole" }
```

`data` significa «esto ya existe, solo léelo». No hay un solo `aws_iam_role` en
todo el proyecto porque **el laboratorio no permite crear roles de IAM**. Se
reutiliza el `LabRole` de la cuenta tanto para el plano de control como para los
nodos. En una cuenta normal serían dos roles distintos, cada uno con el mínimo
privilegio. Está registrado en el ADR 0015.

```hcl
scaling_config { min_size = 0 }
lifecycle { ignore_changes = [scaling_config[0].desired_size] }
```

El `min_size = 0` permite **apagar sin destruir**: bajas los nodos a cero, dejas
de pagar las máquinas y conservas el clúster. El `ignore_changes` es lo que
impide que el siguiente `apply` te vuelva a encender lo que apagaste.

```hcl
resource "aws_vpc_security_group_ingress_rule" "nodeports_desde_elb"
```

Esta regla la pondría Kubernetes solo, en una cuenta normal, al crear el
balanceador. Aquí no puede: el `LabRole` no le deja modificar grupos de
seguridad. Sin ella el ELB se crea con buena pinta pero sus comprobaciones de
salud nunca llegan. Fue el fallo que más tiempo costó diagnosticar, y por eso
lleva veinte líneas de comentario encima.

### `modules/balanceador/` — el ELB (3 recursos)

| Archivo | Líneas | Contenido |
|---|---|---|
| `variables.tf` | 14 | `vpc_id`, subredes, `asg_nodos`, `nodeport_frontend` |
| `main.tf` | 82 | grupo de seguridad, ELB clásico, enganche al autoescalado |
| `outputs.tf` | 8 | `dns` — la URL pública de la tienda |

**Este módulo no debería existir.** En cualquier cuenta normal, un Service de
tipo `LoadBalancer` hace que Kubernetes cree el ELB, lo mantenga y lo borre.
Aquí el `LabRole` no le da permisos de escritura sobre ELB, y el síntoma fue un
balanceador creado una sola vez, con la comprobación de salud apuntando a un
`nodePort` viejo, que ni se actualizaba ni se borraba al borrar el Service.

La salida fue invertir la responsabilidad: el Service pasa a `NodePort` con
puerto **fijo**, y el balanceador lo declara Terraform. Más código, y a cambio
es reproducible — destruir y recrear da exactamente lo mismo.

```hcl
health_check { target = "TCP:${var.nodeport_frontend}" }
listener     { instance_port = var.nodeport_frontend }
```

Los dos leen la misma variable, así que no pueden desincronizarse entre sí. Lo
que sí puede desincronizarse es esa variable contra el manifiesto de Kubernetes;
de ahí el aviso en `variables.tf`.

```hcl
resource "aws_autoscaling_attachment" "nodos" {
  autoscaling_group_name = var.asg_nodos
  elb                    = aws_elb.frontend.id
}
```

Engancha el balanceador al grupo de autoescalado en vez de a instancias
concretas. Por eso apagar y encender los nodos no exige tocar nada: los nuevos
se registran solos.

---

## 5. El script de arranque

### `bootstrap/crear-bucket-estado.sh` — 38 líneas

Crea el bucket de S3 donde vive el estado. Se corre **una vez**, y no lo hace
Terraform a propósito.

El motivo está en el ADR 0013: la política de la organización del laboratorio
(una SCP) deniega `s3:GetBucketObjectLockConfiguration`, y el proveedor de AWS
hace esa consulta al releer el bucket justo después de crearlo. El bucket se
crea bien **y el `apply` falla igual**. Con la CLI no ocurre.

Es el clásico problema del huevo y la gallina: Terraform necesita un sitio donde
guardar el estado antes de poder crear nada, incluido ese sitio.

---

## 6. Qué se versiona y qué no

| Archivo | ¿En Git? | Por qué |
|---|---|---|
| `*.tf` | **sí** | es el código |
| `terraform.tfvars` | **sí** | configuración, no secretos; sin él nadie reproduce |
| `backend.hcl.ejemplo` | **sí** | la plantilla del backend, con el bucket falso |
| `backend.hcl` | no | el bucket real de cada máquina |
| `.terraform.lock.hcl` | **sí** | fija las versiones exactas del proveedor, como `go.sum` |
| `.terraform/` | no | 680 MB de binario descargado; se regenera con `init` |
| `*.tfstate` | no | **contiene secretos en claro**; vive en S3 |
| `*.tfplan` | no | temporal |
| `errored.tfstate` | no | residuo de una operación fallida |

Las dos primeras filas van contra lo que traía el `.gitignore` de Google, que
ignoraba `*.tfvars` y `*.lock.hcl`. Están recuperadas con excepciones
explícitas y un comentario que dice por qué.

---

## 7. Estado actual del entorno

Destruido y limpio: `terraform state list` no devuelve nada y el `plan` dice
**21 to add**. Ese 21 es el total real de los tres módulos (12 + 6 + 3); si
alguna vez sale otro número, algo cambió y hay que entender qué.

### Los tres residuos que `destroy` no se lleva

Un `terraform destroy` borra lo que Terraform creó, y nada más. Kubernetes y EKS
crean cosas por su cuenta dentro de la VPC, y esas se quedan bloqueando el
borrado con `DependencyViolation`:

| Lo que queda | Quién lo creó | Cómo se ve |
|---|---|---|
| grupo de seguridad `k8s-elb-…` | el controlador de Kubernetes, para un Service de tipo LoadBalancer | sobrevive aunque el ELB ya no exista |
| interfaz `aws-K8S-i-…` | el CNI, para dar IPs a los pods | queda en `available` si el nodo muere con pods encima |
| grupo `eks-cluster-sg-…` | EKS mismo, al crear el clúster | debería irse con el clúster; a veces se rezaga |

Los tres se borran con la CLI y eso **no** contradice la regla de *todo en
Terraform*: Terraform gestiona lo que declara, y esto es basura que dejó otro
sistema. `apagar.sh` los barre antes del `destroy` final, y sobre todo hace
`kubectl delete` **antes** de tocar AWS: si los pods se van primero, el CNI
devuelve sus interfaces solo y los otros dos casi nunca aparecen.

---

## 8. Los comandos

Siempre desde `infra/aws/envs/dev`. Terraform trabaja sobre el directorio actual
y desde cualquier otro sitio verá una carpeta vacía o se negará a destrabar el
estado.

```bash
cd infra/aws/envs/dev

terraform init      # descarga el proveedor y se conecta al bucket del estado
terraform plan      # dice qué haría, sin hacerlo
terraform apply     # lo hace
terraform destroy   # lo deshace, en orden inverso

terraform output    # vuelve a imprimir url_tienda y comando_kubeconfig
```

`kubectl`, en cambio, se corre **desde la raíz del repositorio**, porque
`kubernetes-manifests/` es una ruta relativa a ella:

```bash
cd ../../../..
kubectl apply -k kubernetes-manifests/
```

Confundir los dos directorios fue una fuente recurrente de errores que no se
parecen en nada a su causa.
