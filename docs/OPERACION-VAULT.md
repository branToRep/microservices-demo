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
