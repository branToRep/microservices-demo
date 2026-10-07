# 0019 · Vault en su propia maquina: 8200 publico con TLS, sin SSH, y GitHub por OIDC

- **Estado:** aceptada
- **Issues:** #87 a #94 (milestone M12 Fase III - Seguridad)

## Contexto
Antes de anadir funciones hay que proteger la cadena de despliegue. Hasta la
v2.2.0 las tres credenciales del laboratorio se copiaban a los secretos de
GitHub en cada sesion, y cualquier workflow de cualquier rama podia leerlas.

La rubrica pide un Vault fuera del cluster, accesible solo por el 8200,
instalado con Ansible, con motor KV, politica ACL de minimo privilegio y un
token unico con el que el pipeline (`hashicorp/vault-action`) extrae los
secretos e inyecta los del despliegue.

Restricciones que mandan:
- El cluster se destruye al final de cada sesion (`apagar.sh`).
- La cuenta no permite crear roles de IAM (ADR 0015), ni un proveedor OIDC de
  IAM (`iam:CreateOpenIDConnectProvider` denegado).
- Los runners de GitHub no tienen IP fija, y el equipo trabaja desde redes que
  cambian.
- Ansible no corre en Windows, que es lo que usa parte del equipo.

## Flujo de secretos

### Que habia y a donde va

| Secreto | Hasta la v2.2.0 | Con Vault |
|---|---|---|
| Credenciales del laboratorio (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) | Secretos del repositorio, copiados en cada sesion; los leia cualquier workflow de cualquier rama | `boutique/aws` en Vault. El pipeline las lee con un token de 10 minutos. GitHub no guarda ninguna |
| `GITHUB_TOKEN` (publicar en GHCR) | Lo genera GitHub por ejecucion | Sin cambios: ya es efimero |
| Redis del carrito y de las listas | **Sin contrasena**: cualquier pod del cluster puede leer y borrar | Identificado. Candidato a `boutique/redis` (pendiente de decidir) |
| Nombre del bucket del estado | `backend.hcl`, fuera del repositorio | Sin cambios: no es secreto |

### Los secretos propios de Vault

| Que | Donde vive | Quien |
|---|---|---|
| Las 5 partes de la llave (Shamir, umbral 3) | El gestor de contrasenas de cada persona | Una parte por persona; nadie tiene tres |
| Token raiz | Solo durante la configuracion; despues se revoca | Nadie |
| Llave privada de la CA | El disco de datos de la maquina (`0600 root`) | Nadie la descarga |
| Certificado de la CA | `infra/vault/ca.pem`, versionado | Es publico |

### Como viaja un secreto hasta el despliegue

```
 push a main
    │
    ▼
 GitHub Actions ── pide a GitHub un token OIDC firmado:
    │              "repo branToRep/microservices-demo, ref main, entorno produccion"
    ▼
 Vault :8200 (TLS) ── metodo jwt, rol 'despliegue': comprueba firma y reclamos
    │                 → token de Vault, 10 min, politica ci-lectura
    ▼
 vault-action ── lee boutique/data/aws (solo lectura; nada mas)
    │
    ▼
 helm upgrade --install → EKS
```

Si Vault esta sellado o apagado, el pipeline no recibe nada y el despliegue se
**salta con un aviso**. No hay respaldo en GitHub: si lo hubiera, un Vault
sellado pasaria desapercibido.

## Decision
1. **Vault en una EC2 aparte, con su propio estado de Terraform**
   (`infra/aws/envs/vault`) y su propia VPC (`10.1.0.0/16`). `apagar.sh` no lo
   ve, asi que los secretos, las politicas y las llaves sobreviven a las
   sesiones. Los datos van en un disco EBS aparte: si la instancia se
   reemplaza, el disco se vuelve a montar.
2. **Solo el 8200 abierto, a `0.0.0.0/0`, siempre con TLS.** La proteccion es
   la autenticacion y las politicas, no la IP. TLS con una CA propia (no hay
   dominio); su certificado publico se versiona en `infra/vault/ca.pem`.
   La tienda sigue en el 80 del balanceador, sin cambios.
3. **Sin SSH.** El 22 esta cerrado y `sshd` apagado. Ansible y las personas
   entran por AWS Systems Manager (Session Manager), que autentica con las
   credenciales de AWS. Funciona desde cualquier red sin tocar reglas.
4. **Ansible desde GitHub Actions** (`vault-servidor.yml`), con la conexion
   `aws_ssm` y el inventario dinamico `aws_ec2`. Nadie instala Ansible.
5. **El token unico lo emite Vault por OIDC (metodo `jwt`)**, sin ningun token
   guardado en GitHub. Cada ejecucion recibe uno propio de diez minutos. El rol
   `despliegue` solo acepta `main` en el entorno `produccion`; el rol `ci`,
   cualquier rama de este repositorio. Un fork no obtiene nada.
6. **Shamir 5/3** y almacenamiento **Raft** (integrado, sin permisos de AWS,
   con copias por `raft snapshot`). La inicializacion y la apertura las hace
   una persona desde su PC, nunca un workflow, para que las partes no acaben en
   un log. `levantar.sh` pide las partes por teclado al empezar la sesion.
   Despues de configurar, el token raiz se revoca.

## OIDC hacia AWS no es OIDC hacia Vault
El laboratorio deniega `iam:CreateOpenIDConnectProvider`, asi que GitHub **no
puede** entrar a AWS por OIDC: es un limite medido. Lo que se usa aqui es otra
cosa: GitHub entra a **Vault** por OIDC. Vault solo necesita descargar las
llaves publicas de GitHub (`token.actions.githubusercontent.com`); no toca IAM.

## Alternativas descartadas
- **Vault dentro de EKS con su chart de Helm:** se borraria cada tarde con el
  cluster, y Ansible no tendria nada que hacer.
- **8200 abierto solo a IPs concretas:** los runners de GitHub usan miles de
  rangos que cambian (un grupo de seguridad admite ~60 reglas). Exigiria un
  runner propio.
- **SSH con lista de IPs:** el equipo cambia de red a menudo. **SSH abierto a
  todo el mundo:** funciona, pero deja el 22 expuesto a bots. Queda como plan B
  si Session Manager no funcionara en el laboratorio.
- **Token estatico de Vault, o AppRole, en los secretos de GitHub:** un secreto
  de larga duracion que cualquier rama puede usar y hay que rotar a mano.
- **Let's Encrypt:** necesita un dominio y abrir el 80 o el 443.
- **Auto-unseal con AWS KMS:** no habria apertura por Shamir, que es parte del
  objetivo.

## Relacion con la rubrica
| Paso | Donde |
|---|---|
| 1 · EC2 fuera del cluster | `infra/aws/envs/vault`, `infra/aws/modules/vault` |
| 2 · Solo el 8200 | `aws_security_group.vault`: una regla de entrada, 8200/tcp |
| 3 · Flujo de secretos | Este ADR, seccion "Flujo de secretos" |
| 4 · Topologia | Este ADR y `docs/VAULT.md` |
| 4–5 · Ansible, `vault.hcl` con `ui = true` y listener | `infra/ansible/` |
| 6 · Idempotencia | Segunda corrida de Ansible con `changed=0` |
| 7 · Init, unseal, KV, UI | `scripts/vault/`, `https://<ip>:8200/ui` |
| 8 · ACL minima y token unico | `infra/vault/politicas/ci-lectura.hcl`, roles `jwt` |
| 9 · `hashicorp/vault-action` | `.github/actions/credenciales-aws` |
| 10–11 · Integracion y resiliencia | Pendientes; se documentan en el portafolio |

## Consecuencias
- Despues de cada arranque de la maquina, **Vault esta sellado** y hacen falta
  tres partes para abrirlo. Mientras esta sellado, el despliegue se salta.
- Depende de que `LabInstanceProfile` permita SSM. Si no lo permite, la
  alternativa es abrir el 22 con llaves por persona y fail2ban.
- El arranque necesita credenciales en los secretos de GitHub una sola vez,
  solo para el workflow que instala Vault. Se borran al terminar.
- Coste aproximado con el laboratorio abierto: 0,026 USD/h (t3.small + IP
  elastica). Detenida, solo la IP y los discos.
- **La rotacion exige un redespliegue:** `vault-action` lee el secreto al
  desplegar. Propagarlo en caliente necesitaria Vault Agent Injector.
- **El clon limpio ya no basta para tener secretos:** quien clone levanta la
  infraestructura e inicializa **su** Vault, con **sus** llaves.
