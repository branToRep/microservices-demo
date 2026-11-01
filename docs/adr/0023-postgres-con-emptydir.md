# 0023 · Postgres con emptyDir, sin volumen persistente

- **Estado:** aceptada
- **Issues:** #64

## Contexto

El `userservice` necesita una base de datos en el cluster. Lo normal seria un
`PersistentVolumeClaim`: Postgres pide un volumen, el aprovisionador le da un
disco EBS, y los datos sobreviven a que el pod muera.

En **este** cluster eso no funciona, y el motivo es verificable:
`infra/aws/modules/cluster/main.tf` instala tres addons —`vpc-cni`, `coredns` y
`kube-proxy`— y ninguno mas. Sin `aws-ebs-csi-driver` no hay quien atienda un
PVC: el objeto se crea, se queda en `Pending` para siempre, y el pod se queda
en `Pending` con el. El evento dice `waiting for a volume to be created`, que no
menciona el addon que falta ni sugiere instalarlo.

Y aunque estuviera: `scripts/aws/apagar.sh` destruye el cluster al final de cada
sesion del laboratorio, porque los nodos y el balanceador cuestan dinero y las
credenciales caducan igual. No hay ninguna sesion en la que los datos de la
sesion anterior pudieran seguir ahi.

## Decision

El Deployment de `postgres` monta un `emptyDir` en `/var/lib/postgresql/data`.
Los datos viven mientras viva el pod, y se pierden cuando muere.

Dos detalles que no son opcionales y van comentados en la plantilla:

- **`PGDATA` apunta a un subdirectorio** del volumen
  (`/var/lib/postgresql/data/pgdata`), no a su raiz. `initdb` se niega a usar un
  directorio con permisos de grupo o de todos —*data directory has group or
  world access*— y un `emptyDir` con `fsGroup` llega en `0775`. El
  subdirectorio lo crea `initdb`, con `0700`.
- **`replicas: 1` y `strategy: Recreate`.** Con `emptyDir`, cada replica tendria
  su propia base vacia y el Service repartiria entre ellas: dos replicas aqui no
  son alta disponibilidad, son dos bases que se contradicen. `RollingUpdate`
  levantaria la nueva antes de matar la vieja, con el mismo efecto durante la
  transicion.

Es el mismo criterio que ya seguian los dos Redis, que montan `emptyDir` en
`/data` desde que existe el chart.

## Alternativas descartadas

**Instalar `aws-ebs-csi-driver` y usar un PVC.** Es el camino correcto para una
base de datos de verdad, y es lo que habria que hacer el dia que los datos
importen. Hoy anade un addon y un disco EBS que cuesta dinero, para conservar
datos que `apagar.sh` va a tirar en la misma sesion. El ADR 0015 ya dejo dicho
que el laboratorio no permite crear roles propios; el driver ademas quiere su
cuenta de servicio con permisos de EBS, que es justo lo que no se puede dar.

**Un `hostPath`.** Sobrevive al pod, pero esta atado al nodo: si el pod se
reprograma en otro, encuentra un directorio vacio y nadie avisa. Es
`emptyDir` con una promesa falsa encima.

**Postgres fuera del cluster (RDS, o en la instancia de Vault).** RDS no cabe en
el presupuesto del laboratorio. Meterlo en la instancia de Vault mezclaria la
base de la aplicacion con la infraestructura de secretos: un reinicio para
actualizar Postgres tumbaria Vault, y el ADR 0020 separo esa instancia a
proposito.

**Un StatefulSet.** Resuelve la identidad estable de las replicas, que es un
problema que aqui no existe con una sola, y sigue necesitando un PVC para
aportar algo. Seria la forma correcta *junto con* el driver de EBS, no en vez
de el.

## Consecuencias

- Cada `levantar.sh` empieza con la base vacia. El Job de migracion aplica
  `schema.sql` en cada despliegue, que por eso usa `CREATE TABLE IF NOT EXISTS`.
- Los usuarios que se registren en una sesion no estan en la siguiente. Para la
  demostracion hay que crear la cuenta en el momento.
- Rotar la contrasena de Postgres en Vault reinicia el pod y, con ello,
  reinicializa la base vacia. Esta razonado en la plantilla `vault.yaml`: la
  alternativa —no reiniciarlo— deja al `userservice` con la contrasena nueva
  contra un Postgres que conserva la vieja, que es una caida total.
- El dia que los datos tengan que sobrevivir, el cambio es: addon
  `aws-ebs-csi-driver` en el modulo del cluster, `volumeClaimTemplates` en un
  StatefulSet, y cambiar la contrasena dentro de Postgres y no solo en Vault.
  Queda escrito aqui para no tener que redescubrirlo.
