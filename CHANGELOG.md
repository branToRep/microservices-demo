# Registro de cambios

Todas las versiones publicadas de este proyecto, la mas reciente arriba.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y la numeracion sigue [Versionado Semantico](https://semver.org/lang/es/).
La convencion concreta de este repositorio esta en [`docs/VERSIONADO.md`](docs/VERSIONADO.md).

## [Sin publicar]

La Fase III esta cerrada en la 2.12.2: Vault como unica fuente del secreto de
Redis, configurada con Ansible, leida por el propio cluster y probada contra
fallos (`docs/PORTAFOLIO-FASE-III.md`). Lo que queda es producto, sin numero
de version asignado: se numera al empezarlo, segun `docs/VERSIONADO.md`.

### Pendiente
- (#63) El `userservice` completo. Es el unico ticket que es programar de
  verdad; el detalle heredado del plan original esta como lista de comprobacion
  en ese issue. El esquema de su tabla ya esta desde la 2.1.0.
- (#64) Desplegarlo en el cluster, con su Postgres. Sus credenciales serian el
  segundo secreto de Vault, por el mismo camino que la contrasena de Redis.
- (#65) El inicio de sesion. Restaura ademas el cableado que quito la 1.5.1
  (ADR 0017), asi que sera el diff mas grande del proyecto.

### Mejoras posibles, no bloqueantes
- Construir tambien las diez imagenes de Google, para no depender de su registro.
  Hoy usamos las oficiales fijadas a `v0.10.6`; anadirlas a la matriz del
  workflow es una linea. No se hace porque no hemos tocado ese codigo.
- Activar la aprobacion manual del despliegue: el trabajo ya declara
  `environment: produccion`; basta anadirle "Required reviewers" en los ajustes
  del repositorio, sin tocar el workflow.
- `apagar.sh --solo-nodos`, para bajar los nodos sin destruir el plano de
  control cuando se va a volver el mismo dia.
- Desellar con AWS KMS (*auto-unseal*) en vez de llaves por teclado. Hoy no se
  puede: el laboratorio no deja crear el rol de IAM que lo autorizaria.

## [2.12.2] - 2026-10-26

**Un cambio solo al chart vuelve a desplegar.** *Publicar y desplegar* filtra por
rutas, y la lista se habia quedado en la 1.x: incluia `kubernetes-manifests/**`
y no `charts/**`, aunque desde la 2.2.0 se despliega con el chart.

PARCHE: se corrige algo que ya estaba.

### Corregido
- `.github/workflows/publicar-y-desplegar.yml` — `charts/**` en vez de
  `kubernetes-manifests/**`. La cabecera explica que rutas lo disparan y por que.
- `docs/infra.md` — el `nodePort` del frontend y el comando de despliegue
  apuntaban todavia a `kubernetes-manifests/`.

### Resultado medido
- El merge de este PR dispara *Publicar y desplegar* (toca el propio workflow):
  _pendiente (enlace a la corrida y su resultado)_.
## [2.12.1] - 2026-10-22

**Las pruebas de resiliencia** (Paso 11 de la lamina). Se rompio Vault a
proposito de cuatro maneras con la tienda en marcha, y el diseno aguanto en
todas: la tienda depende de Vault para arrancar, no para seguir viva. No cambia
codigo.

PARCHE: se documenta y se mide algo que ya estaba.

### Anadido
- `docs/PRUEBAS-DE-RESILIENCIA.md` — el procedimiento, el resultado y la
  respuesta a cada pregunta de la lamina.

### Cambiado
- `docs/adr/0020` — "Como se va a comprobar" pasa a "Como se comprobo": las
  once filas con su resultado y la version donde se midio.
- `CHANGELOG.md`, puesto al dia:
  - `[Sin publicar]` describia el estado de antes de la Fase III y numeraba
    como pendientes versiones ya usadas (2.1.0, 2.2.0, 2.3.0). Ahora lo pendiente
    no lleva numero hasta empezarse.
  - La 2.1.0 tiene por fin su seccion.
  - Los "Resultado medido" que quedaban sin rellenar en la 2.6.0, la 2.8.0 y
    la 2.9.0.
  - Los enlaces de comparacion del pie, que se habian quedado en la 2.2.0.

### Resultado medido
- **Vault inaccesible** con la tienda corriendo: el carrito sigue funcionando,
  el Secret `redis-cart` sigue en el cluster y reiniciar `cartservice` funciona
  igual.
- **El token caduca** (Vault inaccesible mas de 10 min): el operador no puede
  leer mientras Vault esta caida y sellada; al desellar, obtiene un token nuevo
  solo. El pipeline no tiene token que pueda caducar.
- **La politica pierde `read`**: `permission denied`, el valor nuevo no llega
  al Secret y los pods no se reinician. `configurar-vault.yml` la devuelve con
  `changed=1` y el operador reinicia los pods con el valor nuevo.
- **Arranque en frio con Vault caida**: `levantar.sh` se detiene en el paso 7
  ("Vault no responde... levantar-vault.sh") y la tienda no se despliega.

## [2.12.0] - 2026-10-20

**El cluster lee la contrasena de Vault.** El Vault Secrets Operator entra con
la ServiceAccount `lector-vault`, lee `secret/boutique/redis-cart`, crea el
Secret `redis-cart` y lo mantiene al dia. `redis-cart` exige la contrasena desde
el primer despliegue. Rotarla es escribir en Vault: en un minuto los pods se
reinician solos, sin Helm ni pipeline (Pasos 9 y 10, segun el ADR 0020).

MENOR: capacidad nueva. El chart **requiere** desde ahora el operador en el
cluster (lo instala `levantar.sh`); para desplegar sin Vault,
`--set vault.activa=false,contrasenaRedis.activa=false`.

### Anadido
- `charts/boutique/templates/vault.yaml` — la ServiceAccount `lector-vault`, el
  `VaultAuth` (metodo `jwt`, `auth/eks/`, rol `boutique`, audiencia `vault`) y el
  `VaultStaticSecret` (lee cada 60 s; si cambia, reinicia los dos deployments
  que usan la contrasena).
- `charts/boutique/values.yaml`, `vault` — los nombres que tienen que coincidir
  con el rol de Vault. Ni direcciones ni secretos.
- `scripts/aws/conectar-operador-vault.sh` — el operador como release aparte,
  version fija `1.6.0`; la CA de la Vault del operador en el Secret `vault-ca`; y
  la `VaultConnection` `vault` con su direccion, verificando TLS.
- `docs/OPERACION-VAULT.md`, seccion 7 — rotar, y volver a la version anterior.

### Cambiado
- `contrasenaRedis.activa` — `true` por defecto.
- `Chart.yaml` — `version: 1.2.0`.
- `scripts/aws/levantar.sh` — nueve pasos: el octavo conecta el cluster a Vault,
  antes de la tienda. Si el despliegue falla, dice donde mirar si el Secret no
  llego.

### Sin cambios, a proposito
- `.github/workflows/publicar-y-desplegar.yml` — el pipeline despliega con el
  mismo comando. No pide tokens, no lee secretos y no sabe a que Vault apunta el
  cluster.

### Resultado medido
- `VaultStaticSecret` sincronizado y el carrito funcionando:  Normal  SecretSynced 80s (x2 over 80s)  VaultStaticSecret  Secret synced.
- La auditoria registra la lectura de `lector-vault`: {"hora":"2026-10-21T00:45:29.287646858Z","quien":"eks-system:serviceaccount:default:lector-vault","ruta":"secret/data/boutique/redis-cart"}.
- Rotacion: valor nuevo en Vault, pods reiniciados en 80 s, carrito
  vivo: yes.

## [2.11.0] - 2026-10-20

**Vault ya sabe reconocer al cluster.** El metodo `jwt` en `auth/eks/` y el rol
`boutique`: un token de la ServiceAccount `lector-vault`, firmado por el emisor
OIDC de EKS, entra con `boutique-lectura` durante 10 minutos, y ninguna otra
cuenta entra. `levantar.sh` le dice a Vault, en cada sesion, cual es el emisor
del cluster de hoy. Todavia no lo usa nadie: el operador que entra con ese token
es la v2.12.0.

MENOR: capacidad nueva. `levantar.sh` necesita desde ahora la Vault del
operador levantada y su usuario.

### Anadido
- `ansible/roles/vault_config/tasks/jwt.yml` — el metodo y el rol, comparados
  campo a campo con `defaults/main.yml` y escritos solo si difieren
  (`changed=0` en la segunda corrida).
- `scripts/aws/avisar-a-vault.sh` — comprueba que Vault responda (si esta
  sellada, pide las llaves por teclado), que haya una sesion del operador (si
  no, `vault login` con su usuario, sin imprimir el token) y escribe el emisor
  del cluster en `auth/eks/config`. Se puede correr solo, con el cluster ya
  levantado.
- `docs/OPERACION-VAULT.md`, seccion 6.

### Cambiado
- `scripts/aws/levantar.sh` — ocho pasos. El primero comprueba **todas** las
  herramientas (`kubectl`, `helm`, `vault`, `jq`...) antes de crear nada: una que
  faltaba en el paso 5 dejaba un cluster cobrando mientras se instalaba. El
  septimo es `avisar-a-vault.sh`, antes de desplegar la tienda.
- `docs/OPERACION-VAULT.md`, 5.1 — las tres trampas de crear el usuario.
- `docs/adr/0020` — medido: Vault llega a las llaves del emisor de EKS.

### Resultado medido
- `configurar-vault.yml` con el usuario: changed=2 y changed=0 al
  repetir.
- Un token de `lector-vault` con audiencia `vault` entra con
  `boutique-lectura` y lee la ruta: ["password"].
- Otra ServiceAccount, u otra audiencia: rechazadas: Error writing data to secret/data/boutique/redis-cart: Error making API request.

## [2.10.0] - 2026-10-17

**El chart sabe exigir la contrasena de Redis.** `redis-cart` puede arrancar con
`--requirepass` y `cartservice` enviarla, los dos leyendola de un Secret de
Kubernetes que el chart solo nombra. Apagado por defecto hasta que el operador
de Vault (v2.11.0) cree ese Secret en cada cluster.

MENOR: capacidad nueva; apagada, el chart produce exactamente lo mismo que la
1.0.0.

### Anadido
- `charts/boutique/values.yaml`, `contrasenaRedis` — `activa` (por defecto
  `false`), `secreto: redis-cart` y `clave: password`. El valor no esta en el
  chart, ni aqui ni en ninguna plantilla.
- `usaContrasenaRedis: true` en `redis-cart` (la exige) y en `cartservice` (la
  envia). `redis-wishlist` sigue sin contrasena: no es de esta fase.

### Cambiado
- `templates/redis.yaml` — con la contrasena activa, `args: ["--requirepass",
  "$(REDIS_PASSWORD)"]` y `REDIS_PASSWORD` desde el Secret.
- `templates/servicios.yaml` — `REDIS_PASSWORD` va **primero** en la lista de
  variables: Kubernetes solo sustituye `$(REDIS_PASSWORD)` si se declaro antes,
  y las de `env` salen en orden alfabetico (`REDIS_ADDR` delante). A
  `REDIS_ADDR` se le anade `,password=$(REDIS_PASSWORD)`, que StackExchange.Redis
  acepta: `cartservice` no cambia de codigo (ADR 0019).
- `Chart.yaml` — `version: 1.1.0`. `appVersion` no cambia: la aplicacion es la
  misma.

### Resultado medido
- Apagada: `helm template` identico al de `main` salvo la etiqueta
  `helm.sh/chart` (1.0.0 → 1.1.0).
- Encendida, con un Secret de prueba: secret/redis-cart created (el carrito funciona; `redis-cli
  ping` sin contrasena da `NOAUTH`)_.
- Contrasena distinta en Redis y en `cartservice`: AUTH failed (el carrito falla)_.

## [2.9.0] - 2026-10-15

**Ya no hay token raiz.** Una politica de solo lectura para el cluster, una de
administracion para la persona, acceso con usuario y contrasena con tokens que
caducan, y el raiz revocado (Paso 8 de la lamina).

MENOR: capacidad nueva.

### Anadido
- `ansible/roles/vault_config/files/politicas/` — las politicas como archivos
  del repositorio, que Ansible compara y reescribe si difieren:
  - `boutique-lectura`: **leer una sola ruta**, nada mas. Es la del cluster.
  - `operador`: administrar esta Vault, sin ser raiz. Cubre exactamente lo que
    necesita `configurar-vault.yml` para repetirse sin raiz.
- `ansible/roles/vault_config/tasks/politicas.yml` y `usuarios.yml` — el metodo
  `userpass` y el usuario de la persona, con tokens de 1 h (hasta 8 h). Su
  contrasena entra por el entorno y no se imprime; si el usuario ya existe, no
  se toca.
- `docs/OPERACION-VAULT.md`, seccion 5 — entrar como uno mismo, poner a prueba
  la politica de solo lectura, revocar el raiz y como regenerarlo con las
  llaves si alguna vez hiciera falta.

### Cambiado
- `ansible/roles/vault_config/defaults/main.yml` — el token se toma de
  `VAULT_TOKEN` o, si no, de `~/.vault-token` (donde lo deja `vault login`).
- `ansible/README.md` — la descripcion del rol.
- `CHANGELOG.md` — la fecha y parte del resultado medido de la 2.8.0.

### Resultado medido
- `configurar-vault.yml` repetido **con el usuario, sin raiz**: `changed=0`.
  Medido otra vez en la 2.11.0, ya con el raiz revocado: `changed=2` al anadir
  el metodo `jwt` y `changed=0` al repetir.
- Token de `boutique-lectura` (5 min): `kv get` lee la ruta y devuelve
  `["password"]` sin el valor; `kv put`, `kv list secret/boutique` y
  `secrets list` dan `403 permission denied`.
- El token raiz revocado: `vault token lookup` con el, `403`: Denied

## [2.8.0] - 2026-10-10

**Vault guarda el primer secreto.** Inicializada, desellada, con el registro de
auditoria activo, el motor KV v2 montado y la contrasena de Redis dentro
(Paso 7 de la lamina).

MENOR: capacidad nueva.

### Anadido
- `docs/OPERACION-VAULT.md` — inicializar (3 fragmentos, 2 para desellar), donde
  guardar las llaves, desellar sin dejar llaves en el historial, configurar y
  comprobar sin revelar el secreto. **Inicializar es manual a proposito.**
- `ansible/configurar-vault.yml` y `ansible/roles/vault_config/` — por la API de
  Vault, desde la maquina del operador, verificando TLS contra la CA propia:
  - el registro de auditoria **primero**, para que lo demas ya quede registrado;
  - KV v2 en `secret/`;
  - la contrasena de Redis: 32 caracteres alfanumericos (va dentro de una
    cadena de conexion, donde una coma la partiria), generada y escrita sin
    imprimirse; si ya existe, no se toca.
  - Separado de `site.yml`: aquel configura la maquina sin secretos; este
    necesita un token y solo corre cuando hace falta.

### Cambiado
- `.github/workflows/terraform-ci.yml` — `ansible-lint` y `--syntax-check`
  incluyen `configurar-vault.yml`.
- `ansible/README.md` — el playbook nuevo y el enlace al documento.

### Resultado medido
- `vault status`: `Seal Type shamir`, `Total Shares 3`, `Threshold 2`,
  `Initialized true`, version `1.21.4`. Tras dos llaves, `Sealed false`; desde la
  2.11.0 lo comprueba `avisar-a-vault.sh` ("Vault desellada en ...").
- `configurar-vault.yml`, primera corrida `changed=3`, segunda `changed=0`
  (2026-10-10).
- `vault kv metadata get secret/boutique/redis-cart`: `current_version 1`,
  creada el 2026-10-10T21:42:48Z con `operation: create`; el valor no aparece.
- `vault audit list` muestra `file/`; sin token, `403 permission denied`.
- Una linea del registro de auditoria con la ruta y los valores en HMAC:
  _{"hora":"2026-10-27T00:29:24.400571241Z","ruta":"secret/data/boutique/redis-cart","quien":"eks-system:serviceaccount:default:lector-vault","token":"hmac-sha256:ce9eede89e74432121fc790374227c92845410981262e62efa44e4460cbbe4f8"}_.

## [2.7.0] - 2026-10-10

**La prueba de fuego.** La maquina de Vault se destruye en una cuenta de AWS y se
recrea desde cero en **otra**, con un comando, y la segunda corrida no cambia
nada (Paso 6 de la lamina).

MENOR: un comando nuevo que antes no existia.

### Anadido
- `scripts/aws/levantar-vault.sh` — de una cuenta vacia a Vault respondiendo:
  comprueba requisitos y credenciales, Terraform, enciende la maquina si el
  laboratorio la detuvo, **espera a que aparezca en SSM** y corre Ansible.
  - Planifica antes de aplicar, y **se detiene si el plan borra o reemplaza**
    algo: esta maquina guarda los datos de Vault en su disco.
  - `terraform init -reconfigure`: cambiar de cuenta (de bucket) no pregunta si
    migrar el estado de la otra.
  - **No hay `apagar-vault.sh`, a proposito**: destruir Vault no puede estar a
    un comando de distancia.
- `docs/PRUEBA-DE-FUEGO.md` — el procedimiento y el resultado.

### Cambiado
- `ansible/README.md`, `docs/infra.md` — apuntan al script.
- `.gitignore` — `*.log`: los de la prueba son evidencia, no codigo.
- `CHANGELOG.md` — la fecha de la 2.6.0, pendiente.

### Resultado medido
Ver `docs/PRUEBA-DE-FUEGO.md`.

## [2.6.0] - 2026-10-09

**El CI revisa Ansible.** `ansible-lint` (perfil `production`) y
`ansible-playbook --syntax-check` corren en cada PR, dentro del check que ya
bloquea la fusion.

MENOR: el pipeline gana un control que antes no tenia.

### Cambiado
- `.github/workflows/terraform-ci.yml`:
  - el trabajo **"Formato y sintaxis"** instala `ansible-core` 2.18 y
    `ansible-lint` 26.9.0 (versiones fijas) y revisa `ansible/`. En el mismo
    trabajo y no en uno nuevo: es el que exige la proteccion de `main`, asi que
    un hallazgo de Ansible bloquea la fusion desde el primer dia, sin tocar la
    configuracion del repositorio.
  - el flujo pasa a llamarse "CI de infraestructura": ya no es solo Terraform.
    El archivo conserva su nombre.
- `ansible/README.md` — `ansible-lint` local con la misma version que el CI.

### Resultado medido
- El control en verde en el PR #108 y en cada PR fusionado desde entonces
  (#111 a #121): es obligatorio, sin el no se fusiona.
- El control en rojo: no se provoco a proposito en el CI. `ansible-lint` si
  detuvo una violacion real en local durante la 2.5.0 (`no-handler`), que se
  corrigio con un handler notificado antes de abrir el PR.

## [2.5.0] - 2026-10-09
**Vault corre.** El rol `vault` la instala, la configura y la deja respondiendo
por TLS con la UI encendida (Pasos 4 y 5 de la lamina). Queda sin inicializar a
proposito: las llaves de desellado se generan a mano, en el ticket siguiente.

MENOR: capacidad nueva.

### Anadido
- `ansible/roles/vault/`:
  - **Instalacion desde el repositorio de HashiCorp, verificando la huella de
    su llave de firma.** HashiCorp la roto el 2026-09-10; si vuelve a cambiar,
    el playbook se detiene en vez de confiar en una llave que nadie miro.
  - **Version fijada (`1.21.*`) y paquete retenido**, para que el
    `apt upgrade` del rol base no la mueva: actualizar Vault es una decision.
  - **CA propia, restringida** con name constraints a la IP de esta Vault,
    `127.0.0.1` y `localhost`, y el certificado del servidor firmado por ella.
    La llave de la CA no sale de la maquina; `ca.crt` (publico) se copia a
    `~/.vault-boutique/` del operador.
  - `vault.hcl`: `ui = true`, solo TLS 1.2+, almacenamiento en archivo, mlock.
  - Directorio y rotacion del registro de auditoria (se activa al inicializar).
  - Comprobacion de salud por TLS **verificando contra la CA**.
  - Reinicio solo si cambia `vault.hcl` (sella Vault, y lo avisa); renovar el
    certificado o rotar el registro solo **recarga**, que no sella.
- `ansible/README.md` — la CLI de Vault en WSL y como confiar en la CA en Windows.

### Cambiado
- `ansible/site.yml` — aplica `vault` despues de `base`.
- `ansible/requirements.yml` — `community.crypto` 3.5.0.

### Resultado medido
- Primera corrida de `site.yml` con el rol `vault`: localhost: ok = 2 / vault-boutique: ok = 36 changed = 18 skipped = 1
- Segunda corrida seguida, `changed=0`: localhost: ok = 2 / vault-boutique: ok = 32 changed = 0 skipped = 1
- `vault status` desde WSL, verificando con la CA: Initialized false, Sealed true, Build Date 2026-03-04T17:40:05Z

## [2.4.0] - 2026-10-09

**Ansible entra en el proyecto.** La estructura del repositorio de Ansible y un
primer rol, `base`, aplicados a la maquina de Vault. Vault todavia no: eso es el
siguiente rol, sobre esta base.

MENOR: capacidad nueva. La tienda y la infraestructura no cambian.

### Anadido
- `ansible/` — `ansible.cfg`, inventario, `site.yml`, `requirements.yml` con
  versiones fijas y un README con los comandos exactos.
  - **Sin ids ni IP escritos a mano.** La primera jugada pregunta a
    `terraform output` que maquina es; recrearla no exige editar nada.
  - **Se entra por SSH dentro de un tunel SSM** (ADR 0020), configurado en
    `group_vars/vault.yml`: el repositorio no depende del `~/.ssh/config` de
    nadie.
- `ansible/roles/base/`:
  - actualizaciones de seguridad automaticas, **sin reinicio automatico**:
    Vault se sella al reiniciar;
  - hora con Amazon Time Sync, dentro de la VPC (el grupo de seguridad no deja
    salir NTP), y zona UTC para que los registros se puedan comparar;
  - SSH endurecido aunque el 22 no este abierto: sin contrasenas, sin root,
    solo el usuario `ubuntu`;
  - aviso, y no reinicio, cuando una actualizacion lo pide.

### Cambiado
- `CHANGELOG.md` — la fecha y el resultado medido de la 2.3.0, pendientes.

### Resultado medido
- Primera corrida de `site.yml`: localhost: ok = 2 / vault-boutique: ok = 14 changed = 14 skipped = 1
- Segunda corrida seguida, `changed=0`: localhost: ok = 2 / vault-boutique: ok = 12 changed = 0 skipped = 1

## [2.3.0] - 2026-10-09

**La maquina de Vault existe.** Un entorno de Terraform propio,
`infra/aws/envs/vault/`, que `apagar.sh` no toca. Todavia no tiene Vault
instalado: eso lo pone Ansible en los tickets siguientes.

MENOR porque es una capacidad nueva que no rompe nada: la tienda se levanta y
se apaga exactamente igual que antes.

### Anadido
- `infra/aws/envs/vault/` — el entorno. Mismo bucket que `envs/dev`, otra
  clave de estado (`vault/terraform.tfstate`); reutiliza `../dev/backend.hcl`.
- `infra/aws/modules/servidor-vault/` — VPC `10.1.0.0/16` con una subred,
  Ubuntu 24.04 en `t3.micro`, IP elastica, disco cifrado, solo IMDSv2.
  **Una sola regla de entrada: 8200.** A la maquina se entra por SSM, con el
  `LabInstanceProfile` que ya trae la cuenta (ADR 0020).
- `docs/infra.md` — seccion 9, el entorno de Vault.

### Cambiado
- `.github/workflows/terraform-ci.yml` — el trabajo "Formato y sintaxis"
  valida tambien `envs/vault`. Con pasos propios y no con una matriz, que
  cambiaria el nombre del check requerido y bloquearia todos los PR.
- `scripts/aws/apagar.sh` — el barrido de residuos busca la VPC por
  `Proyecto=boutique` **y** `Entorno=dev`. Con dos VPC del proyecto en la
  cuenta, la busqueda antigua podia encontrar la de Vault.
- `.gitignore` — las excepciones de `terraform.tfvars` y del lockfile para
  `envs/vault`, y una red de seguridad para llaves privadas.
- `docs/adr/0020-...md` — el numero de su issue (#99), que faltaba.
- `CHANGELOG.md` — la entrada de la 2.2.2 y la fecha de la 2.2.1, que faltaban.

### Resultado medido
- `AWS-StartSSHSession` contra la instancia: funciona (2026-10-09). `ssh` por el
  tunel SSM devuelve `ubuntu` con el grupo de seguridad sin regla para el 22.
- Disco cifrado aceptado por el laboratorio: si (2026-10-08), `terraform apply`
  sin errores.

## [2.2.2] - 2026-10-08

El diseno de la 2.2.1 choca con tres cosas medidas despues, y se corrige antes
de construir nada. No cambia infraestructura ni despliegue.

### Anadido
- `docs/adr/0020-una-vault-por-operador-ssm-y-cluster-que-lee.md`:
  - **Una Vault por operador**, en su propia cuenta de AWS, con el mismo codigo.
    Una compartida dejaria a uno sin secreto cada vez que el laboratorio del
    otro esta cerrado.
  - **Se entra por SSM**, medido en el laboratorio: el grupo de seguridad abre
    solo el 8200, como pide la lamina. Ansible usa SSH dentro del tunel.
  - **El cluster lee el secreto** con el Vault Secrets Operator. El pipeline ya
    no toca Vault, y rotar la contrasena no exige redesplegar.

### Cambiado
- `docs/adr/0019-flujo-de-secretos-con-vault.md` — marcada como reemplazada en
  parte por la 0020, y con el numero de su issue (#97), que faltaba.

Esta entrada se escribio con la 2.3.0: el PR #100 se fusiono sin ella.

### Lo que esta version se aparta de la lamina
Los Pasos 9 y 10 piden que el pipeline lea el secreto con `vault-action` y lo
inyecte. Aqui lo lee el cluster. Aprobado por el profesor a condicion de
documentarlo; la justificacion completa esta en el ADR.

## [2.2.1] - 2026-10-06

Primer paso de la **Fase III**: el diseno de la gestion de secretos, escrito
antes de crear nada. No cambia infraestructura ni despliegue.

### Anadido
- `docs/adr/0019-flujo-de-secretos-con-vault.md` — que secreto migra a Vault (la
  contrasena de `redis-cart`), donde vive Vault (una EC2 en su propio entorno de
  Terraform y su propia VPC, fuera de lo que destruye `apagar.sh`) y como entra
  el pipeline: con el **token OIDC de GitHub**, validado por Vault. GitHub no
  guarda ninguna credencial de Vault, y una rama que no sea `main` no puede
  leer el secreto.

### Lo que esta version declara
- Rotar la contrasena exige redesplegar: se lee en tiempo de despliegue.
- El puerto 8200 queda abierto a internet; lo protegen TLS y la autenticacion.
- El 22 se abre solo a la IP del operador, para Ansible. La lamina pedia
  exclusivamente el 8200; la excepcion queda escrita en el ADR.

## [2.2.0] - 2026-09-26

El despliegue pasa de Kustomize a un **Helm Chart propio**, `charts/boutique/`.
No es el `helm-chart/` que trae el repositorio de Google: ese tiene 2673 lineas,
esta orientado a GCP y no conoce nuestro `wishlistservice`. El nuestro son 584.

### Anadido
- `charts/boutique/` — Chart.yaml, values.yaml y cinco plantillas.
- `docs/adr/0018-helm-en-vez-de-kustomize.md`
- `.github/workflows/terraform-ci.yml` — trabajo **Chart de Helm**: `lint`,
  `template` y una comprobacion de que salen 38 objetos con `kind` y nombre. No
  necesita credenciales, asi que es obligatorio como el formato de Terraform.

### Cambiado
- `.github/workflows/publicar-y-desplegar.yml` — `kubectl set image` pasa a
  `helm upgrade --install --atomic`.
- `scripts/aws/levantar.sh` — `kubectl apply -k` pasa a `helm upgrade --install`.
  Comprueba que Helm este instalado y lo dice si falta.
- `scripts/aws/apagar.sh` — `kubectl delete -k` pasa a `helm uninstall`. Con el
  borrado por kustomization quedaban vivos los objetos que Helm creo.
- `kubernetes-manifests/kustomization.yaml` — se quita `wishlistservice.yaml` y
  se anade una cabecera diciendo que **esto ya no es el camino de despliegue**.
  Los manifiestos se conservan: son la referencia legible y la que permite
  `git diff` contra upstream.

### Por que, si Kustomize funcionaba
Dos razones, y la segunda pesa mas a largo plazo:

1. **La rubrica** pide desplegar «mediante un Helm Chart personalizado».
2. **Vault y lo que venga.** Vault, cert-manager, external-secrets, kyverno — todo
   ese ecosistema se distribuye como charts. Con Kustomize habria que usar Helm
   igual para ellos, o renderizarlos y congelar su version. Y `dependencies` en
   `Chart.yaml` permite meter Vault como subchart apagable por bandera; Kustomize
   no tiene ese concepto.

Lo que el chart aporta por si mismo: diez de los catorce deployments tienen forma
identica, asi que salen de **una** plantilla y diez entradas en `values.yaml`, en
vez de diez archivos de noventa lineas casi iguales. Cambiar algo comun es una
edicion y no diez.

### Corregido durante la migracion
`helm lint` paso y `helm template` renderizo sin errores. **Y eso no basta.** La
comparacion objeto por objeto contra los manifiestos encontro **dos errores que
habrian roto la tienda**, ninguno visible para el lint:

- El Service de `emailservice` expone el puerto **5000** y escucha en 8080.
  Asumir que coincidian dejaba a `checkoutservice` —que lo busca en
  `emailservice:5000`— sin poder llamarlo.
- Al frontend le faltaba `SHOPPING_ASSISTANT_SERVICE_ADDR`. Ese servicio no se
  despliega, pero `main.go` la lee con `mustMapEnv`, que entra en panico si falta:
  el frontend no habria arrancado.

Mas dieciocho diferencias de tiempos de sonda, por homogeneizarlos cuando los
manifiestos los tenian variados. Se corrigieron igual.

Tras las correcciones, **cero diferencias en los 38 objetos**: imagenes, puertos
de contenedor y de Service, variables, recursos, sondas con sus tiempos,
serviceAccounts, securityContext y selectores.

La leccion vale mas que el chart: **lo que encontro los errores fue comparar
contra la verdad conocida, no validar contra un esquema.**

### Lo que esta version cuesta
Hace falta **Helm instalado**, y eso rompe parte de la promesa de la v1.5.0: antes
`kubectl apply -k` no pedia nada extra. Queda anotado en
`docs/PRUEBA-CLON-LIMPIO.md`, que habra que repetir.

Ademas ya no se lee el YAML que se aplica, se leen plantillas — que es
exactamente por donde se colaron los dos errores de arriba.

A cambio, `--atomic` revierte la release **entera** si algo no cuaja. El
`kubectl rollout undo` anterior revertia deployment por deployment, asi que un
fallo a medias podia dejar el frontend nuevo hablando con un `wishlistservice`
viejo.

## [2.1.0] - 2026-09-25

**El esquema de la tabla `users`, y un punto de entrada en el README.** Primer
paso del `userservice` (#62). Esta seccion se anadio despues, en la 2.12.1: el
PR #83 cambio el CHANGELOG para reordenar lo pendiente, pero no abrio su propia
version.

MENOR: capacidad nueva (el esquema), sin romper nada.

### Anadido
- `src/userservice/schema.sql` — el esquema de la tabla `users`, recuperado.
- `README.md` — un bloque al principio: que anade este fork sobre la tienda de
  Google y por donde empezar a leer.
- `scripts/crear-issues-versionado.sh` — crea los issues de lo pendiente, uno
  por version prevista.

### Cambiado
- `CHANGELOG.md`, `[Sin publicar]` — lo pendiente, ordenado por version.

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

[Sin publicar]: https://github.com/branToRep/microservices-demo/compare/v2.12.2...HEAD
[2.12.2]: https://github.com/branToRep/microservices-demo/compare/v2.12.1...v2.12.2
[2.12.1]: https://github.com/branToRep/microservices-demo/compare/v2.12.0...v2.12.1
[2.12.0]: https://github.com/branToRep/microservices-demo/compare/v2.11.0...v2.12.0
[2.11.0]: https://github.com/branToRep/microservices-demo/compare/v2.10.0...v2.11.0
[2.10.0]: https://github.com/branToRep/microservices-demo/compare/v2.9.0...v2.10.0
[2.9.0]: https://github.com/branToRep/microservices-demo/compare/v2.8.0...v2.9.0
[2.8.0]: https://github.com/branToRep/microservices-demo/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/branToRep/microservices-demo/compare/v2.6.0...v2.7.0
[2.6.0]: https://github.com/branToRep/microservices-demo/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/branToRep/microservices-demo/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/branToRep/microservices-demo/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/branToRep/microservices-demo/compare/v2.2.2...v2.3.0
[2.2.2]: https://github.com/branToRep/microservices-demo/compare/v2.2.1...v2.2.2
[2.2.1]: https://github.com/branToRep/microservices-demo/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/branToRep/microservices-demo/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/branToRep/microservices-demo/compare/v2.0.0...v2.1.0
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
