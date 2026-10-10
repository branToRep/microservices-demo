# Ansible — la maquina de Vault

Terraform crea la maquina (`infra/aws/envs/vault`); esto configura lo que corre
dentro. Nada se instala a mano. Diseno en los ADR 0019 y 0020.

## Requisitos, una vez por operador (en WSL o Linux)

```bash
sudo apt-get install -y pipx && pipx ensurepath   # y abrir otra terminal
pipx install --include-deps ansible-core==2.18.*
pipx install ansible-lint==26.9.0                  # la misma version que el CI
```

Ademas, lo mismo que pide `envs/vault`: la AWS CLI con credenciales vigentes,
el `session-manager-plugin` y la llave `~/.ssh/boutique-vault`. **No** hace
falta tocar `~/.ssh/config`: la forma de entrar va en `group_vars/vault.yml`.

## Correrlo

```bash
cd ansible                                            # ansible.cfg se lee de aqui
export ANSIBLE_CONFIG=$PWD/ansible.cfg                # en WSL sobre /mnt/c, ver abajo
ansible-galaxy collection install -r requirements.yml # una vez, y al cambiar versiones
ansible-lint site.yml roles/                          # revisar; SIEMPRE con objetivos
ansible-playbook site.yml --check --diff              # que cambiaria, sin cambiar nada
ansible-playbook site.yml                             # aplicarlo
```

La segunda corrida seguida tiene que terminar en `changed=0`: es la prueba de
que el playbook es idempotente.

## Como esta organizado

| Archivo | Que hace |
|---|---|
| `ansible.cfg` | inventario, roles, colecciones locales, salida legible, `pipelining` |
| `inventario.yml` | solo `localhost` y un grupo `vault` vacio |
| `site.yml` | jugada 1: pregunta a Terraform que maquina es; jugada 2: la configura |
| `group_vars/vault.yml` | como se entra: SSH dentro de un tunel SSM, sin puerto 22 |
| `requirements.yml` | colecciones con version fija |
| `.ansible-lint` | perfil `production`, sin descargas; se corre con `site.yml roles/` |
| `roles/base/` | actualizaciones, hora, endurecimiento de SSH |
| `roles/vault/` | Vault desde el repositorio firmado de HashiCorp, CA propia, TLS, UI |

El id de la instancia no esta escrito en ningun sitio: cambia cada vez que la
maquina se recrea, y `site.yml` lo lee de `terraform output` en cada corrida.

## En WSL, con el repositorio en una carpeta de Windows

WSL presenta las carpetas de `/mnt/c` como escribibles por cualquiera, y Ansible
**ignora** un `ansible.cfg` en un directorio asi (para que nadie le cuele una
configuracion). El sintoma es un aviso `world writable directory` y, despues,
errores que parecen de otra cosa: no encuentra los roles ni el inventario.
`export ANSIBLE_CONFIG=$PWD/ansible.cfg` se lo indica de forma explicita, y eso
si lo respeta.

## Despues del rol `vault`

El playbook deja Vault **escuchando y sin inicializar**. Inicializarla genera las
llaves de desellado y el token raiz, y eso se hace a mano, una vez (ticket
siguiente): si lo hiciera un script, las llaves acabarian en un archivo.

### La CLI de Vault, en WSL

```bash
sudo apt-get install -y vault                       # mismo repositorio que Terraform
export VAULT_ADDR=$(terraform -chdir=../infra/aws/envs/vault output -raw vault_addr)
export VAULT_CACERT=~/.vault-boutique/ca.crt        # lo deja aqui el playbook
vault status                                        # Initialized false, Sealed true
```

`VAULT_CACERT` hace que la CLI **verifique** el servidor contra la CA propia. No
usar `VAULT_SKIP_VERIFY`: es justo lo que TLS existe para impedir.

### La UI sin avisos del navegador

`https://<ip>:8200` muestra un aviso hasta que Windows confie en la CA:

1. Copiar `ca.crt` a Windows. Desde el Explorador:
   `\\wsl$\Ubuntu-24.04\home\<usuario>\.vault-boutique\ca.crt`
2. Doble clic → *Instalar certificado* → *Usuario actual* → *Colocar todos los
   certificados en el siguiente almacen* → **Entidades de certificacion raiz de
   confianza**.
3. Cerrar y abrir el navegador (Edge y Chrome usan el almacen de Windows).

Es seguro porque la CA esta **restringida**: solo puede firmar para la IP de esta
Vault, `127.0.0.1` y `localhost` (name constraints). Si alguien robara su llave,
no podria hacerse pasar por ningun otro sitio.
