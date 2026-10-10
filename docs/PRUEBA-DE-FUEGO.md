# Prueba de fuego: destruir Vault y recrearla desde cero

Paso 6 de la Fase III: **demostrar que la máquina de Vault se destruye y se
recrea sola, desde cero, y que repetir la configuración no cambia nada.** Este
documento es el procedimiento y el registro del resultado.

Se hace con una exigencia más que la lámina: la máquina no se recrea en la misma
cuenta de AWS, sino en **otra**. Recrear en la misma cuenta deja accidentes a
favor —un bucket que ya existe, un `.terraform/` ya inicializado contra él, una
llave importada—; en una cuenta nueva no queda ninguno. Es también lo que la
materia pide del proyecto entero: levantarlo en cualquier sitio, en cualquier
momento (ADR 0020).

## Por qué ahora, y no después

Vault está **sin inicializar**. Destruir la máquina ahora no pierde nada; después
de `vault operator init` perdería las llaves y el secreto. Por eso esta prueba va
antes de configurar Vault, no al final.

## Qué se prueba, exactamente

| | Debe cumplirse |
|---|---|
| 1 | `terraform destroy` en la cuenta original deja `terraform state list` vacío |
| 2 | En la cuenta nueva, lo único hecho a mano es el bucket y su línea en `backend.hcl` |
| 3 | **Ningún archivo del repositorio se edita** |
| 4 | `levantar-vault.sh` lleva la cuenta de nada a Vault respondiendo por TLS, sin intervención |
| 5 | **La segunda corrida no cambia nada**: Terraform `No changes`, Ansible `changed=0` |
| 6 | `vault status` responde verificando contra la CA nueva |

## El procedimiento

### A. En la cuenta original: destruir

```bash
cd infra/aws/envs/vault
terraform destroy          # lee la lista: 12 recursos. Escribir 'yes'
terraform state list       # tiene que salir vacio
```

### B. En la cuenta nueva: lo único manual

```bash
# credenciales de la cuenta nueva en ~/.aws/credentials (las TRES lineas)
bash infra/aws/bootstrap/crear-bucket-estado.sh boutique-tfstate-<sufijo-unico>
# y ese nombre en infra/aws/envs/dev/backend.hcl, que no se versiona
```

### C. Recrear: un comando

```bash
bash scripts/aws/levantar-vault.sh 2>&1 | tee primera-corrida.log
```

### D. Repetir: tiene que no hacer nada

```bash
bash scripts/aws/levantar-vault.sh 2>&1 | tee segunda-corrida.log
grep -E "No changes|changed=" segunda-corrida.log
```

### E. Comprobar

```bash
export VAULT_ADDR=$(terraform -chdir=infra/aws/envs/vault output -raw vault_addr)
export VAULT_CACERT=~/.vault-boutique/ca.crt
vault status
```

Los `.log` no se versionan: son evidencia del portafolio, no código.

## Resultado

- **Fecha:** 2026-10-10
- **Cuenta original → cuenta nueva:** "A → B"

| | Resultado |
|---|---|
| 1 | Destroy succesful |
| 2 | Credentials succesfully created |
| 3 | 0 Failures |
| 4 | 0 changes |
| 5 | localhost: ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 | vault-boutique             : ok=32   changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0 |
| 6 | Initialized: false Sealed:true |

**Lo que falló o sorprendió:** Falta de certificado anterior. Si nada, decirlo: también es un resultado._
