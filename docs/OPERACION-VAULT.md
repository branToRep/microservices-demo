# Operación de Vault: inicializar, desellar, configurar

Paso 7 de la Fase III. La máquina ya existe y Vault responde, sin inicializar
(`scripts/aws/levantar-vault.sh`). Este documento es lo que viene después, y lo
único del proyecto que se hace **a mano a propósito**: inicializar genera las
llaves de desellado, y si lo hiciera un script, las llaves acabarían en un
archivo.

Todo se corre en WSL, desde la raíz del repositorio.

```bash
export VAULT_ADDR=$(terraform -chdir=infra/aws/envs/vault output -raw vault_addr)
export VAULT_CACERT=~/.vault-boutique/ca.crt
vault status                      # Initialized false, Sealed true
```

---

## 1. Inicializar (una sola vez en la vida de esta Vault)

```bash
vault operator init -key-shares=3 -key-threshold=2
```

Imprime **tres llaves de desellado** y **el token raíz**. Es la única vez que se
ven: Vault no los guarda en ningún sitio legible.

- **3 fragmentos, 2 para desellar** (ADR 0019 y 0020). Perder uno no es fatal;
  robar uno no basta.
- **Cada fragmento en un sitio distinto.** Por ejemplo: dos entradas separadas en
  un gestor de contraseñas y la tercera en papel. Nunca los tres juntos.
- **No** redirigir la salida a un archivo, **no** pegarla en un chat ni en un
  issue, **no** hacerle captura sin tapar los valores.
- **El token raíz** se guarda solo hasta terminar la configuración: un ticket
  posterior crea usuarios propios y lo revoca.

> **Si se pierden dos de los tres fragmentos, esta Vault es irrecuperable.** No
> hay puerta trasera, y es lo correcto. Se reconstruye desde cero como en
> `docs/PRUEBA-DE-FUEGO.md` y se vuelve a escribir el secreto.

## 2. Desellar (tras inicializar y tras cada reinicio de la máquina)

```bash
vault operator unseal             # pide una llave, sin mostrarla
vault operator unseal             # otra llave distinta
vault status                      # Sealed false
```

Sin pasar la llave como argumento (`vault operator unseal <llave>`): quedaría en
el historial de la terminal.

Vault vuelve **sellada** cada vez que la máquina se reinicia, también cuando el
laboratorio la detiene al cerrar la sesión. No es un fallo: es el diseño (ADR
0019). Un ticket posterior lo integra en `levantar.sh`.

## 3. Configurar (Ansible, por la API)

El token raíz, **sin que pase por el historial**:

```bash
read -rs VAULT_TOKEN && export VAULT_TOKEN      # pegar el token y Enter; no se ve
cd ansible && export ANSIBLE_CONFIG=$PWD/ansible.cfg
ansible-playbook configurar-vault.yml           # changed=3
ansible-playbook configurar-vault.yml           # changed=0
```

Activa, en este orden:

1. **El registro de auditoría** en `/var/log/vault/audit.log`. Primero, para que
   todo lo que sigue ya quede registrado.
2. **El motor KV v2** en `secret/`. Guarda versiones de cada secreto.
3. **La contraseña de Redis** en `secret/boutique/redis-cart`, clave `password`:
   32 caracteres alfanuméricos, generados por Ansible y escritos directamente en
   Vault. No se imprimen ni pasan por ningún archivo. Si ya existe, no se toca.

**No** usar `vault login` con el token raíz: lo guarda en `~/.vault-token`.

## 4. Comprobar, sin revelar el secreto

Con el token todavía cargado (si se abrió otra terminal, repetir el `read -rs`):

```bash
vault audit list                                  # file/
vault secrets list                                # secret/  kv  ... version:2
vault kv metadata get secret/boutique/redis-cart  # versión 1, fechas; NO el valor
unset VAULT_TOKEN
vault audit list                                  # ahora: 403 permission denied
```

El último `403` también es evidencia: sin identidad, Vault no responde nada que
no sea público.

En la UI (`https://<ip>:8200`, método *Token*): *Secrets Engines* → `secret/` →
`boutique` → `redis-cart`. El valor aparece oculto hasta pulsar el ojo; la
captura va **sin** pulsarlo.

El registro de auditoría, por el túnel SSM:

```bash
ssh $(terraform -chdir=infra/aws/envs/vault output -raw id_instancia) \
  "sudo tail -n 5 /var/log/vault/audit.log" | jq -c '{hora: .time, tipo: .type, ruta: .request.path}'
```

Cada línea dice quién pidió qué ruta y cuándo. Los valores sensibles (tokens,
contraseñas) aparecen como `hmac-sha256:...`: el registro demuestra el acceso
sin filtrar el secreto.

---

## 5. Acceso personal y adiós al token raíz (Paso 8)

El token raíz no caduca, puede todo y en la auditoría solo dice "root". A partir
de aquí cada persona entra con **su usuario**, con tokens de 1 hora (renovables
hasta 8), y el raíz **deja de existir**.

### 5.1 Crear las políticas y el usuario (una vez, todavía con el raíz)

```bash
read -rs VAULT_TOKEN && export VAULT_TOKEN                   # el token raíz
export VAULT_USUARIO=<tu-nombre>                             # p. ej. tu usuario de GitHub
read -rs VAULT_CONTRASENA_NUEVA && export VAULT_CONTRASENA_NUEVA   # 16+ caracteres; al gestor de contraseñas
cd ansible && export ANSIBLE_CONFIG=$PWD/ansible.cfg
ansible-playbook configurar-vault.yml                        # políticas, userpass, usuario
unset VAULT_CONTRASENA_NUEVA
cd ..
```

Crea `boutique-lectura` (leer **una** ruta) y `operador` (administrar esta
Vault), activa el método `userpass` y crea tu usuario con `operador`. Las
políticas viven en `ansible/roles/vault_config/files/politicas/`: si se editan
ahí, la siguiente corrida las reescribe en Vault.

Tres trampas que ya costaron una tarde:

- **`read -rs NOMBRE` lleva el nombre de la variable tal cual.** La contraseña
  se pega *después*, en la línea vacía que queda esperando (no se ve nada: es
  lo normal). Pegarla en lugar del nombre la deja en el historial.
- **Contraseña solo con letras y números.** Un `$`, `!` o comilla la cambia la
  shell sin avisar. `echo ${#VAULT_CONTRASENA_NUEVA}` da la longitud sin
  mostrarla: tiene que ser 16 o más.
- **El usuario se crea en la PRIMERA corrida y después no se toca.** Si se
  repite con otra contraseña, Vault se queda con la primera. Por eso, antes de
  seguir, comprobar que el usuario existe (`vault list auth/userpass/users`) y
  hacer 5.2 en el acto, con el raíz todavía vivo.

### 5.2 Entrar como tú, y comprobar que basta

```bash
unset VAULT_TOKEN
vault login -method=userpass username=$VAULT_USUARIO         # pide la contraseña
vault token lookup | grep -E "display_name|policies|ttl"     # userpass-<tu-nombre>, operador, ~1h
cd ansible && ansible-playbook configurar-vault.yml; cd ..   # changed=0, ya SIN el raíz
```

`vault login` guarda el token en `~/.vault-token`; con el usuario es aceptable,
porque caduca en una hora.

La última línea es la prueba de que `operador` cubre todo lo necesario: el
playbook se puede repetir sin el raíz.

### 5.3 La política de solo lectura, puesta a prueba

Un token con **solo** `boutique-lectura`, de 5 minutos:

```bash
LECTOR=$(vault token create -policy=boutique-lectura -ttl=5m -field=token)

VAULT_TOKEN=$LECTOR vault kv get -format=json secret/boutique/redis-cart | jq '.data.data | keys'
#   ["password"]      <- puede leer (y no se imprime el valor)
VAULT_TOKEN=$LECTOR vault kv put secret/boutique/redis-cart password=otra
#   403 permission denied   <- no puede escribir
VAULT_TOKEN=$LECTOR vault kv list secret/boutique
#   403 permission denied   <- no puede ni listar
VAULT_TOKEN=$LECTOR vault secrets list
#   403 permission denied   <- no ve nada más de Vault

vault token revoke $LECTOR && unset LECTOR
```

Es exactamente lo que tendrá el clúster: leer una ruta y nada más.

### 5.4 Revocar el token raíz

**Solo después de que 5.2 funcione.** Sin el raíz, el usuario es la única forma
de entrar (además de regenerar el raíz con las llaves, abajo).

```bash
read -rs RAIZ                                     # el token raíz, por última vez
VAULT_TOKEN=$RAIZ vault token revoke -self        # Success! Revoked token
VAULT_TOKEN=$RAIZ vault token lookup              # 403 permission denied
unset RAIZ
```

Borrarlo también del gestor de contraseñas: ya no sirve para nada.

**Si algún día hace falta raíz** (por ejemplo, si se pierde la contraseña del
usuario), se genera uno nuevo con 2 de los 3 fragmentos de desellado:
`vault operator generate-root -init`, y después `vault operator generate-root`
con cada fragmento. Es el procedimiento de emergencia de Vault; no hace falta
para nada del día a día.

### 5.5 La UI, como tú

`https://<ip>:8200`, método **Username**. La captura del portafolio va con tu
usuario arriba a la derecha, no con *root*.

---

## 6. Cada sesión con el clúster: decirle a Vault en cuál confiar (ADR 0020)

El clúster entra a Vault con el método `jwt` en `auth/eks/`: Vault comprueba la
firma de los tokens de su ServiceAccount `lector-vault` con las llaves públicas
del emisor OIDC de EKS. Ese emisor **cambia cada vez que el clúster se crea**.

- **Una vez:** el método y el rol `boutique` los pone `configurar-vault.yml`
  (sección 3), con tu usuario. Es configuración permanente.
- **Cada sesión:** el emisor del clúster de hoy lo escribe
  `scripts/aws/avisar-a-vault.sh`. Lo llama `levantar.sh` antes de desplegar;
  con el clúster ya levantado se puede correr solo:

```bash
bash scripts/aws/avisar-a-vault.sh
#   Vault desellada en https://<ip>:8200
#   Sesion de userpass-<tu-usuario>
#   Vault confia en el cluster de hoy: https://oidc.eks.us-east-1.amazonaws.com/id/...
```

Si Vault está sellada, pide dos llaves por teclado; si no hay sesión tuya, te
pide entrar con tu usuario. Con el emisor de ayer, Vault rechaza al clúster de
hoy, y el carrito no arranca: el fallo se ve, no pasa en silencio.

El rol solo admite tokens con audiencia `vault` y sujeto
`system:serviceaccount:default:lector-vault`, y da `boutique-lectura` durante
10 minutos. Otra ServiceAccount del mismo clúster no entra.

---

## 7. Rotar la contraseña de Redis, sin redesplegar (ADR 0020)

Desde la v2.12.0 el clúster lee la contraseña él solo: el Vault Secrets Operator
entra con la ServiceAccount `lector-vault` (sección 6), vuelve a leer
`secret/boutique/redis-cart` cada minuto y, si cambió, actualiza el Secret
`redis-cart` y reinicia `redis-cart` y `cartservice`.

Rotar es escribir un valor nuevo en Vault. Nada más: ni Helm, ni el pipeline.

```bash
vault kv put secret/boutique/redis-cart password="$(openssl rand -hex 16)"
#   version 2. El valor lo genera openssl: no se ve ni queda en el historial.
kubectl get pods -l 'app in (redis-cart,cartservice)' -w
#   en un minuto o menos, los dos se reinician solos (Ctrl+C para salir)
kubectl describe vaultstaticsecret redis-cart | tail -n 5
#   eventos: el Secret sincronizado y el reinicio de los dos deployments
```

Solo letras y números (`openssl rand -hex`): `cartservice` recibe la contraseña
dentro de una cadena de conexión, donde una coma la partiría.

El carrito se vacía (Redis sin volumen, a propósito) y vuelve a funcionar en
cuanto los dos pods están listos.

**Volver a la anterior**, si la nueva diera problemas: KV v2 guarda las
versiones.

```bash
vault kv rollback -version=1 secret/boutique/redis-cart   # crea una version 3 igual a la 1
```

