# Las imágenes del proyecto

Dos imágenes son nuestras. Las otras nueve son las públicas de Google, fijadas a
una versión concreta en los manifiestos.

| Imagen | De dónde sale |
|---|---|
| `ghcr.io/brantorep/frontend` | `src/frontend/` — la tienda con listas de deseos |
| `ghcr.io/brantorep/wishlistservice` | `src/wishlistservice/` — el servicio de listas |

Las construye `.github/workflows/publicar-imagenes.yml` en cada push a `main`
que toque `src/frontend/`, `src/wishlistservice/` o `protos/`. Nadie construye
nada en su portátil.

## Las etiquetas

Cada publicación pone dos:

```
ghcr.io/brantorep/frontend:a8a7ede     ← el SHA corto del commit
ghcr.io/brantorep/frontend:main        ← la última de main
```

**La del SHA es la que usan los despliegues.** Identifica exactamente qué código
corre, y volver atrás es apuntar a otro SHA. `:main` es solo comodidad para
mirar el registro; desplegar por `:main` haría imposible saber qué versión está
viva, que es el problema clásico de `:latest`.

## Por qué solo `linux/amd64`

El runner de GitHub es amd64 y los nodos `t3.medium` también, así que no hace
falta emulación y la construcción es rápida.

Esto importa porque construir en un Mac (arm64) produce imágenes que arrancan en
local y fallan en el clúster con `exec format error` — un mensaje que no menciona
la arquitectura por ninguna parte. Es una de las razones de que la construcción
viva en el CI y no en una máquina de desarrollo.

## Por qué no está el loadgenerator

El plan original incluía una tercera imagen. `src/loadgenerator/locustfile.py` en
este repositorio es el de Google **sin modificar**: no genera tráfico de listas
de deseos. Publicar una imagen idéntica a la pública no aporta nada. Entrará
cuando el `locustfile.py` tenga tráfico nuestro.

## Lo único que hay que configurar una vez: la visibilidad

**Los paquetes de GHCR nacen privados.** Una imagen privada no la puede descargar
el clúster: los nodos de EKS no tienen credenciales de GitHub, y el pod se queda
en `ImagePullBackOff` con un `401 Unauthorized` que parece un problema de red.

Hay dos salidas, y para este proyecto la primera es la sensata:

### 1. Hacer los paquetes públicos (recomendada)

Las imágenes no contienen secretos: son la tienda de demostración de Google con
dos funciones añadidas. Públicas, cualquiera las descarga sin credenciales y el
clúster funciona sin configuración extra.

Lo hace el **dueño del paquete** (`branToRep`), una vez por imagen, tras la
primera publicación:

```
github.com/branToRep?tab=packages
  → frontend → Package settings → Danger Zone → Change visibility → Public
  → lo mismo con wishlistservice
```

### 2. Un `imagePullSecret` en el clúster

Si se quieren mantener privadas, el clúster necesita credenciales. Hace falta un
token personal con permiso `read:packages`:

```bash
kubectl create secret docker-registry ghcr \
  --docker-server=ghcr.io \
  --docker-username=<usuario> \
  --docker-password=<token-con-read:packages> \
  --docker-email=<correo>
```

Y cada Deployment que use una imagen nuestra necesita:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr
```

Es más fiel a lo que se hace en producción, y a cambio mete un secreto que hay
que crear a mano en cada clúster nuevo — justo lo que la serie 1.x se dedicó a
eliminar. Por eso se elige la opción 1.

## Comprobar qué hay publicado

```bash
gh api /users/branToRep/packages/container/frontend/versions \
  --jq '.[0:5][] | {creado: .created_at, etiquetas: .metadata.container.tags}'
```

O a ojo en `github.com/branToRep?tab=packages`.
