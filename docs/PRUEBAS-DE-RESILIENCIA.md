# Pruebas de resiliencia: romper Vault a propósito

Paso 11 de la Fase III: **simular fallos críticos y validar que el diseño
aguanta.** La lámina hace tres preguntas: ¿qué pasa si el token expira?, ¿y si
la política ACL cambia?, ¿y si Vault se sella? Este documento es el
procedimiento, el resultado y la respuesta a cada una.

Se hicieron el 2026-10-22, en una sola sesión, con el clúster de esa sesión y
la Vault de la cuenta de `branToRep`.

## Lo que se esperaba, y por qué

El diseño (ADR 0020) hace una promesa que la versión de la lámina no podía
hacer: **la tienda depende de Vault para arrancar, no para seguir viva.** El
Vault Secrets Operator copia la contraseña en un Secret de Kubernetes y la
vuelve a leer cada minuto. Si Vault falla, lo que se detiene es esa relectura;
lo ya copiado sigue sirviendo. Y como el pipeline no lleva ningún token de
Vault, no hay nada en él que pueda caducar ni filtrarse.

Para un arranque en frío, en cambio, sin Vault no hay contraseña, y entonces no
debe haber tienda: el fallo tiene que verse, no quedar a medias.

## Resumen

| Fallo simulado | Lo esperado | Resultado |
|---|---|---|
| **Vault inaccesible** con la tienda corriendo | la tienda sigue con el último Secret; solo se detiene la relectura | **cumple** |
| **El token caduca** | el operador pide otro solo; el pipeline no tiene ninguno | **cumple** |
| **La política pierde `read`** | `permission denied`; el Secret no cambia y los pods no se reinician | **cumple** |
| **Arranque en frío con Vault caída** | `levantar.sh` se detiene con el motivo, antes de desplegar | **cumple** |

Y dos que ya estaban medidos en versiones anteriores:

| Fallo simulado | Resultado | Dónde |
|---|---|---|
| Contraseña incorrecta | el carrito falla (`AUTH failed`) y vuelve con la buena | `v2.10.0` |
| Otra ServiceAccount, u otra audiencia | Vault rechaza el login | `v2.11.0` |

---

## 1. Vault inaccesible con la tienda corriendo

Se detiene la máquina de Vault. Es más que sellarla: al volver arranca
**sellada**, así que cubre los dos casos. (`vault operator seal` no está al
alcance de la política `operador`, a propósito: no necesita `sys/seal` para el
día a día.)

```bash
ID=$(terraform -chdir=infra/aws/envs/vault output -raw id_instancia)
aws ec2 stop-instances --region us-east-1 --instance-ids "$ID"
aws ec2 wait instance-stopped --region us-east-1 --instance-ids "$ID"

kubectl get secret redis-cart                    # sigue ahi
kubectl rollout restart deploy/cartservice && kubectl rollout status deploy/cartservice
kubectl describe vaultstaticsecret redis-cart | tail -n 5
```

**Resultado:**
- Añadir productos al carrito **sigue funcionando**.
- El Secret `redis-cart` **sigue en el clúster**.
- Reiniciar `cartservice` **funciona igual**: el pod nuevo lee la contraseña
  del Secret, que ya está en Kubernetes. Vault no hace falta para eso.
- El `VaultStaticSecret` registra que no puede leer de Vault. Es lo único que
  se detiene.

**Respuesta a "¿qué pasa si Vault se sella?":** la tienda no se entera. Se
pierde la rotación hasta que alguien la deselle; nada más.

![La tienda funcionando con Vault detenida](img/fase-3/24-vault-caida-tienda-viva.png)

## 2. El token caduca

El token que Vault da al clúster dura 10 minutos (`token_ttl` del rol
`boutique`). La prueba es la anterior, alargada: Vault inaccesible **más de 10
minutos**, de forma que el token del operador caduca sin que pueda renovarlo.

```bash
# pasados mas de 10 minutos con la maquina detenida:
bash scripts/aws/levantar-vault.sh               # la enciende; vuelve sellada
kubectl describe vaultstaticsecret redis-cart | tail -n 5
vault operator unseal                            # llave 1
vault operator unseal                            # llave 2
kubectl describe vaultstaticsecret redis-cart | tail -n 5
ssh $ID "sudo grep auth/eks/login /var/log/vault/audit.log | tail -n 3" \
  | jq -c 'select(.type=="response") | {hora: .time, quien: .auth.display_name}'
```

**Resultado:**
- Mientras Vault estaba detenida y después sellada, el operador **no pudo leer
  el secreto**: el `VaultStaticSecret` lo registra, y dice que Vault está
  sellada.
- Al desellar, el operador **obtuvo un token nuevo por sí solo**: un login
  nuevo de `lector-vault` en la auditoría, y el Secret sincronizado otra vez.
  Nadie tocó el clúster.

**Respuesta a "¿qué pasa en el pipeline si el token expira?":** nada, porque el
pipeline no tiene token de Vault. Es la ventaja directa de que el clúster lea
el secreto (ADR 0020). En el clúster, el token caduca cada 10 minutos por
diseño, y el operador lo repone solo.

![El operador sin poder leer, con Vault sellada](img/fase-3/25-vault-sellada-sin-lectura.png)
![Un login nuevo de lector-vault tras desellar](img/fase-3/26-token-nuevo.png)

## 3. La política pierde `read`

Se sobrescribe la política en Vault, solo para la prueba, con una que deniega
la ruta. Y, con el permiso quitado, se cambia el valor en Vault: así se ve que
el Secret no se toca.

```bash
vault policy write boutique-lectura - <<'EOF'
path "secret/data/boutique/redis-cart" {
  capabilities = ["deny"]
}
EOF
vault kv put secret/boutique/redis-cart password="$(openssl rand -hex 16)"
sleep 90
kubectl describe vaultstaticsecret redis-cart | tail -n 5
kubectl get pods -l 'app in (redis-cart,cartservice)'
```

Para devolverla, no se arregla a mano: Ansible compara la política con el
archivo del repositorio y la reescribe.

```bash
cd ansible && export ANSIBLE_CONFIG=$PWD/ansible.cfg
ansible-playbook configurar-vault.yml
cd ..
kubectl get pods -l 'app in (redis-cart,cartservice)' -w
```

**Resultado:**
- Con la política cambiada: `permission denied` en el `VaultStaticSecret`. El
  valor nuevo de Vault **no llegó** al Secret, y los pods **no se
  reiniciaron**.
- `configurar-vault.yml` lo arregló con **un solo cambio** (`changed=1`: la
  política, tal como está en el repositorio). En el minuto siguiente el
  operador leyó el valor nuevo y reinició `redis-cart` y `cartservice` solo.

**Respuesta a "¿qué pasa si la política ACL cambia?":** el clúster pierde el
acceso al instante (Vault evalúa las políticas en cada petición) pero no se
rompe nada: sigue con el último valor bueno. Y el repositorio manda: una
política cambiada a mano se corrige corriendo Ansible.

![permission denied con la política cambiada, y los pods sin reiniciar](img/fase-3/27-politica-denegada.png)
![Ansible devuelve la política y los pods se reinician con el valor nuevo](img/fase-3/28-politica-restaurada.png)

## 4. Arranque en frío con Vault caída

Con la máquina de Vault detenida, el script de siempre:

```bash
aws ec2 stop-instances --region us-east-1 --instance-ids "$ID"
aws ec2 wait instance-stopped --region us-east-1 --instance-ids "$ID"
bash scripts/aws/levantar.sh
```

**Resultado:** los pasos 1 a 6 pasan; el **7 se detiene**:

```
ALTO: Vault no responde en https://18.211.13.210:8200.
       Si el laboratorio detuvo la maquina:  bash scripts/aws/levantar-vault.sh
```

La tienda **no se despliega** sin su secreto, y el mensaje dice qué hacer. Con
`levantar-vault.sh` y las dos llaves, se vuelve al punto de partida.

![levantar.sh se detiene en el paso 7 con Vault caída](img/fase-3/29-arranque-en-frio.png)

---

## Lo que se aprendió

- **El punto débil es el arranque, no la operación.** Una vez desplegada, la
  tienda aguanta a Vault caída, sellada o sin permiso. Lo que necesita a Vault
  es levantar un clúster nuevo, y ahí el fallo se ve y se explica.
- **Desellar sigue siendo manual**, y es deliberado (ADR 0019): cada reinicio de
  la máquina deja la rotación detenida hasta que una persona pone dos llaves.
  `levantar.sh` las pide por teclado cuando hacen falta.
- **Ningún fallo exigió tocar el clúster a mano.** El operador se recuperó solo
  en todos los casos en cuanto Vault volvió a responder.
