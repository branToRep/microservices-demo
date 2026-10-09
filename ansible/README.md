# Ansible — la maquina de Vault

Terraform crea la maquina (`infra/aws/envs/vault`); esto configura lo que corre
dentro. Nada se instala a mano. Diseno en los ADR 0019 y 0020.

## Requisitos, una vez por operador (en WSL o Linux)

```bash
sudo apt-get install -y pipx && pipx ensurepath   # y abrir otra terminal
pipx install --include-deps ansible-core==2.18.*
pipx install ansible-lint                          # para revisar antes del PR
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

El id de la instancia no esta escrito en ningun sitio: cambia cada vez que la
maquina se recrea, y `site.yml` lo lee de `terraform output` en cada corrida.

## En WSL, con el repositorio en una carpeta de Windows

WSL presenta las carpetas de `/mnt/c` como escribibles por cualquiera, y Ansible
**ignora** un `ansible.cfg` en un directorio asi (para que nadie le cuele una
configuracion). El sintoma es un aviso `world writable directory` y, despues,
errores que parecen de otra cosa: no encuentra los roles ni el inventario.
`export ANSIBLE_CONFIG=$PWD/ansible.cfg` se lo indica de forma explicita, y eso
si lo respeta.
