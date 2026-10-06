# Vault: puesta en marcha y uso diario

HashiCorp Vault guarda las credenciales de AWS del laboratorio. GitHub Actions
se las pide con un token de diez minutos que GitHub firma en cada ejecucion
(OIDC), asi que **GitHub no guarda ninguna credencial**. Las decisiones y sus
porques estan en el [ADR 0019](adr/0019-vault-fuera-del-cluster.md).

```
                         internet
          ┌──────────────────┴───────────────────┐
          │ :80                                  │ :8200 (TLS)
   ┌──────▼──────┐                        ┌──────▼──────────────┐
   │ ELB tienda  │                        │ EC2 boutique-vault  │
   │ (sin cambio)│                        │  Vault + Raft       │
   └──────┬──────┘                        │  disco de datos EBS │
          │                               └──────▲──────────────┘
   ┌──────▼──────┐   credenciales de AWS         │ token OIDC de GitHub
   │  EKS (dev)  │◄──── GitHub Actions ──────────┘ → token de Vault, 10 min
   └─────────────┘
                    Ansible y personas ── AWS Systems Manager ──► EC2
                    (sin SSH: el 22 esta cerrado)
```

| Pieza | Donde |
|---|---|
| La maquina, su red y su grupo de seguridad | `infra/aws/envs/vault`, `infra/aws/modules/vault` |
| Roles de Ansible `comun` y `vault` | `infra/ansible/` |
| Politicas ACL | `infra/vault/politicas/*.hcl` |
| CA publica del servidor | `infra/vault/ca.pem` |
| Inicializar, abrir, configurar, usuarios | `scripts/vault/` |
| Credenciales de AWS para los workflows | `.github/actions/credenciales-aws` |
| Correr Ansible | workflow **Servidor de Vault (Ansible)** |

---

## Lo que necesita cada PC

- **CLI de Vault.** Windows: `winget install Hashicorp.Vault` (o
  `choco install vault`). macOS: `brew install hashicorp/tap/vault`.
- AWS CLI y `gh`, como hasta ahora.
- Solo para abrir una terminal en la maquina: el
  [plugin de Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

Ansible **no** hace falta: corre en GitHub Actions.

---

## Puesta en marcha (una sola vez)

### 1. Crear la maquina

```bash
cd infra/aws/envs/vault
terraform init -backend-config=../dev/backend.hcl   # mismo bucket que dev, otra clave
terraform apply

# La direccion de Vault, para los workflows y los scripts:
gh variable set VAULT_ADDR --body "$(terraform output -raw vault_addr)"
```

Comprueba que Session Manager la ve (tarda uno o dos minutos):

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].[InstanceId,PingStatus]' --output table
```

Tiene que salir la instancia con `Online`. **Si la lista sale vacia**, el
`LabInstanceProfile` de tu laboratorio no permite SSM, y Ansible no podra
entrar. En ese caso avisa: la alternativa es abrir el 22 con llaves por persona
y fail2ban (ADR 0019).

### 2. Credenciales de arranque en GitHub

El workflow que instala Vault no puede pedirle credenciales a un Vault que aun
no existe. Esta vez van a los secretos de GitHub, como antes:

```bash
./scripts/aws/sincronizar-credenciales.sh --github
```

### 3. Instalar Vault con Ansible

GitHub > **Actions** > **Servidor de Vault (Ansible)** > **Run workflow**.

Al terminar, el resumen dice que la CA no esta versionada. Traela y abre un PR:

```bash
gh run download --name vault-ca --dir infra/vault   # deja infra/vault/ca.pem
git checkout -b chore/vault-ca
git add infra/vault/ca.pem
git commit -m "chore(vault): versiona la CA publica del servidor"
git push -u origin chore/vault-ca
```

`ca.pem` es el certificado **publico** de la CA: no es un secreto. Sin el, ni
los workflows ni la CLI pueden verificar que hablan con tu Vault.

### 4. Inicializar (genera las partes de la llave)

```bash
./scripts/vault/inicializar.sh
```

Deja un archivo `~/vault-init-<fecha>.json` con:
- **cinco partes** de la llave de Shamir (hacen falta tres para abrir), y
- el **token raiz**.

Reparte una parte por persona; cada quien la guarda en su gestor de
contrasenas. Nadie deberia tener tres.

### 5. Abrir

```bash
./scripts/vault/abrir.sh
```

Pide una parte. Hay que meter **tres**, y pueden ser tres personas desde tres
PCs: el progreso lo lleva el servidor.

### 6. Configurar

```bash
export VAULT_TOKEN=<root_token del archivo>
./scripts/vault/configurar.sh
```

Activa la auditoria, el motor KV `boutique/`, las politicas, el metodo de
GitHub (`github-actions/`, roles `ci` y `despliegue`) y `userpass/`.

Despues, una cuenta por persona y las credenciales del laboratorio a Vault:

```bash
./scripts/vault/crear-usuario.sh <tu-nombre> admin
./scripts/vault/crear-usuario.sh <otra-persona> operador

unset VAULT_TOKEN
vault login -method=userpass username=<tu-nombre>
./scripts/aws/sincronizar-credenciales.sh          # ahora a Vault
```

### 7. Cerrar

Cuando ya entres con tu usuario `admin`:

```bash
vault token revoke <root_token>       # el raiz deja de existir
rm ~/vault-init-*.json                # cuando todos tengan su parte
```

Opcional, para que GitHub no guarde **ninguna** credencial de AWS:

```bash
gh secret delete AWS_ACCESS_KEY_ID
gh secret delete AWS_SECRET_ACCESS_KEY
gh secret delete AWS_SESSION_TOKEN
```

El precio: con Vault sellado, el despliegue se salta en vez de usar el respaldo.

---

## Cada sesion del laboratorio

```bash
# 1. Si la maquina de Vault esta detenida, arrancala:
aws ec2 start-instances --instance-ids "$(terraform -chdir=infra/aws/envs/vault output -raw id_instancia)"

# 2. Vault arranca SELLADO: tres partes.
./scripts/vault/abrir.sh

# 3. Las credenciales nuevas del laboratorio, a Vault.
vault login -method=userpass username=<tu-nombre>
./scripts/aws/sincronizar-credenciales.sh

# 4. Lo de siempre.
./scripts/aws/levantar.sh
```

`apagar.sh` no toca Vault. Al cerrar el laboratorio la instancia se detiene,
y al volver esta sellada otra vez.

---

## Quien puede hacer que

| Quien | Como entra | Politica | Puede |
|---|---|---|---|
| Workflow en cualquier rama | OIDC, rol `ci` | `ci-lectura` | leer `boutique/aws` |
| Despliegue (main, `produccion`) | OIDC, rol `despliegue` | `ci-lectura` | leer `boutique/aws` |
| Persona del equipo | `userpass` | `operador` | leer y escribir `boutique/*` |
| Quien administra | `userpass` | `admin` | politicas, metodos, auditoria, secretos |
| Nadie en solitario | — | — | abrir Vault o sacar un token raiz (tres partes) |

Para cambiar una politica: edita `infra/vault/politicas/*.hcl`, fusiona el PR y
corre `./scripts/vault/configurar.sh` con un usuario `admin`.

---

## Problemas conocidos

**El workflow dice "Vault no entrego credenciales; uso los secretos".**
Vault esta sellado o apagado. `./scripts/vault/abrir.sh`.

**`x509: certificate signed by unknown authority`.** `infra/vault/ca.pem` no es
la CA del servidor (o falta). Paso 3.

**`error validating claims` / `permission denied` en el login de GitHub.** El
token de GitHub no cumple el rol: otra rama, otro entorno, o el nombre del
repositorio no coincide en mayusculas con el que tomo `configurar.sh` (variable
`REPO`). La auditoria dice que reclamo fallo:
`aws ssm start-session --target <id>` y
`sudo tail /srv/vault/auditoria/auditoria.log`.

**El workflow de Ansible no encuentra la maquina.** Esta detenida (el
laboratorio la apaga al cerrar), o no tiene las etiquetas `Proyecto=boutique` y
`Rol=vault`.

**Ansible se queda colgado conectando.** Session Manager no ve la instancia
(paso 1) o falta `TF_BUCKET`.

**Copia de seguridad.** Con un usuario `admin`:
`vault operator raft snapshot save vault-$(date +%F).snap`. Guardala fuera del
repositorio: contiene los secretos (cifrados con la llave de Shamir).
