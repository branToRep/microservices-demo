# 0019 · Vault en su propia maquina: 8200 publico con TLS, sin SSH, y GitHub por OIDC

- **Estado:** propuesta
- **Issues:** —

## Contexto
Antes de anadir funciones hay que proteger la cadena de despliegue. Hasta ahora
las tres credenciales del laboratorio se copiaban a los secretos de GitHub en
cada sesion, y cualquier workflow de cualquier rama podia leerlas.

El objetivo es que GitHub Actions se autentique con un token unico antes de
tocar AWS, y que los secretos vivan en HashiCorp Vault: motor KV, politicas ACL
y apertura por partes de una llave de Shamir. Ansible instala Vault y sus
dependencias.

Restricciones que mandan:
- El cluster se destruye al final de cada sesion (`apagar.sh`).
- La cuenta no permite crear roles de IAM (ADR 0015).
- Los runners de GitHub no tienen IP fija, y el equipo trabaja desde redes que
  cambian.
- Ansible no corre en Windows, que es lo que usa parte del equipo.

## Decision
1. **Vault en una EC2 aparte, con su propio estado de Terraform**
   (`infra/aws/envs/vault`). `apagar.sh` no lo ve, asi que los secretos, las
   politicas y las llaves sobreviven a las sesiones. Los datos van en un disco
   EBS aparte: si la instancia se reemplaza, el disco se vuelve a montar.
2. **El 8200 abierto a `0.0.0.0/0`, siempre con TLS.** La proteccion es la
   autenticacion y las politicas, no la IP. TLS con una CA propia (no hay
   dominio); su certificado publico se versiona en `infra/vault/ca.pem`.
   La tienda sigue en el 80 del balanceador, sin cambios.
3. **Sin SSH.** El 22 esta cerrado y `sshd` apagado. Ansible y las personas
   entran por AWS Systems Manager (Session Manager), que autentica con las
   credenciales de AWS. Funciona desde cualquier red sin tocar reglas.
4. **Ansible desde GitHub Actions** (`vault-servidor.yml`), con la conexion
   `aws_ssm` y el inventario dinamico `aws_ec2`. Nadie instala Ansible.
5. **GitHub entra a Vault por OIDC (metodo `jwt`)**, sin ningun token guardado
   en GitHub. Cada ejecucion recibe un token de Vault de diez minutos. El rol
   `despliegue` solo acepta `main` en el entorno `produccion`; el rol `ci`,
   cualquier rama de este repositorio. Un fork no obtiene nada.
6. **Shamir 5/3**: cinco partes, tres para abrir. La inicializacion y la
   apertura las hace una persona desde su PC, nunca un workflow, para que las
   partes no acaben en un log. Despues de configurar, el token raiz se revoca.

## Alternativas descartadas
- **Vault dentro de EKS con su chart de Helm:** se borraria cada tarde con el
  cluster, y Ansible no tendria nada que hacer.
- **8200 abierto solo a IPs concretas:** los runners de GitHub usan miles de
  rangos que cambian (un grupo de seguridad admite ~60 reglas). Exigiria un
  runner propio.
- **SSH con lista de IPs:** el equipo cambia de red a menudo. **SSH abierto a
  todo el mundo:** funciona, pero deja el 22 expuesto a bots.
- **Token estatico de Vault en los secretos de GitHub:** dura mucho, cualquier
  rama puede usarlo y hay que rotarlo a mano.
- **Let's Encrypt:** necesita un dominio y abrir el 80 o el 443.
- **Auto-unseal con AWS KMS:** no habria apertura por Shamir, que es parte del
  objetivo.

## Consecuencias
- Despues de cada arranque de la maquina, **Vault esta sellado** y tres personas
  (o una con tres partes) tienen que abrirlo con `scripts/vault/abrir.sh`.
  Mientras esta sellado, los workflows usan los secretos `AWS_*` si existen, o
  se saltan el despliegue.
- Depende de que `LabInstanceProfile` permita SSM. Si no lo permite, la
  alternativa es abrir el 22 con llaves y fail2ban (ver `docs/VAULT.md`).
- Coste aproximado con el laboratorio abierto: 0,026 USD/h (t3.small + IP
  elastica). Detenida, solo la IP y los discos.
- El arranque necesita credenciales en los secretos de GitHub una vez: el
  workflow que instala Vault no puede pedirselas a un Vault que aun no existe.
