# Prueba en clon limpio

La promesa de la serie 1.x es concreta: **otra persona clona el repositorio y lo
levanta sin editar ningún archivo del proyecto.** Este documento es el
procedimiento para comprobarlo y el registro del resultado.

No basta con que funcione en la máquina donde se escribió. Ahí funciona por
accidentes invisibles: un `.terraform/` ya descargado, un `backend.hcl` que
alguien creó hace semanas, un kubeconfig apuntando al sitio correcto. La prueba
consiste en quitar todos esos accidentes.

## Qué se prueba, exactamente

| | Debe cumplirse |
|---|---|
| 1 | El clon no necesita ningún archivo que no venga de Git |
| 2 | Lo único que se escribe a mano es `backend.hcl`, y es un archivo de dos líneas |
| 3 | **Ningún `.tf` se edita** |
| 4 | `levantar.sh` llega hasta imprimir una URL que responde 200 |
| 5 | `apagar.sh` deja `terraform state list` vacío |

Si algo de eso falla, faltan tickets de la serie 1.x y hay que abrirlos.

## Limitación honesta de esta prueba

El profesor lo levantará en **otra cuenta de AWS**. Aquí se prueba en la misma,
y eso cambia dos cosas:

- **Los nombres chocan.** `proyecto = "boutique"` da un clúster llamado
  `boutique` y un ELB `boutique-frontend`. Dos entornos a la vez en la misma
  cuenta no pueden existir. Por eso la prueba exige que el entorno original esté
  destruido antes de empezar.
- **El `LabRole` ya existe.** En una cuenta normal habría que crearlo, y el
  laboratorio no lo permite (ver ADR 0015). En otra cuenta de AWS Academy existe
  igual, así que para el caso del profesor no es un problema.

Lo que sí se prueba de verdad es el punto 3, que es el que importa: si nadie
edita un `.tf`, la etiqueta significa lo que dice.

## El procedimiento

Con el laboratorio abierto, credenciales frescas, y **el entorno original ya
destruido**.

```bash
# 1. Un clon nuevo, en otra carpeta, desde la etiqueta a probar
cd ~/Desktop
git clone https://github.com/branToRep/microservices-demo.git prueba-limpia
cd prueba-limpia
git checkout v1.5.0

# 2. Un bucket de estado propio, para no compartir estado con el original
./infra/aws/bootstrap/crear-bucket-estado.sh boutique-tfstate-prueba-01

# 3. El unico archivo que se escribe a mano
cd infra/aws/envs/dev
cp backend.hcl.ejemplo backend.hcl
# editar: bucket = "boutique-tfstate-prueba-01"
cd ../../../..

# 4. Levantar
./scripts/aws/levantar.sh

# 5. Abrir la URL que imprime, y comprobar que la tienda carga

# 6. Apagar
./scripts/aws/apagar.sh
```

Después, la comprobación que da sentido a todo:

```bash
git status
```

Tiene que decir que lo único sin seguimiento es `backend.hcl`. **Si aparece
algún `.tf` modificado, la prueba falló**, aunque la tienda haya cargado.

## Resultado: pasó

Ejecutada el **25 de septiembre de 2026** sobre `main` en el commit de la v1.4.1,
en un clon nuevo en `~/Desktop/prueba/prueba-limpia`, con bucket de estado propio
`boutique-tfstate-prueba-01`.

| Punto | Resultado |
|---|---|
| 1. Sin archivos externos | **sí** — el clon salió de Git y nada más |
| 2. Solo `backend.hcl` a mano | **sí** — dos líneas |
| 3. Ningún `.tf` editado | **sí** — `git status --short` no devolvió **nada** |
| 4. `levantar.sh` dio URL con 200 | **sí** — la tienda cargó |
| 5. `apagar.sh` dejó el estado vacío | **sí** — `terraform state list` vacío, sin residuos |

Sobre el punto 3: `git status --short` salió **completamente vacío**, ni siquiera
con `backend.hcl` como archivo sin seguimiento. Es mejor de lo esperado y la
razón es el `.gitignore` de la 1.1.0, que ya lo cubre. Comprobable con:

```bash
git check-ignore -v infra/aws/envs/dev/backend.hcl
```

### Las dos cosas que encontró la prueba

Ninguna se habría visto en la carpeta de trabajo original, y por eso la prueba
tenía sentido.

**Un fallo de lectura en `levantar.sh` y `apagar.sh`.** El `backend.hcl` se
escribió a mano dejando la línea `bucket = ...` duplicada. El `sed` que leía el
nombre imprimía **todas** las coincidencias, así que la variable acabó con un
salto de línea dentro y el script construyó la ruta `s3://bucket\nbucket/`. En la
carpeta original nunca pasó porque ahí ese archivo se genera con `sed`, que
reemplaza en vez de añadir.

Peor que el fallo era **el mensaje**: decía «la sesión del laboratorio terminó,
vuelve a pegar las credenciales», que es mentira y manda a buscar en el sitio
equivocado. Los dos scripts ahora cuentan las coincidencias antes de leerlas y se
detienen diciendo qué pasa de verdad.

**El bucket no se borra con `aws s3 rm`.** El bootstrap le activa versionado, así
que `rm --recursive` quita la versión actual y deja las anteriores; el
`delete-bucket` falla con `BucketNotEmpty`. El procedimiento de limpieza de abajo
está corregido.

Como efecto secundario, esto confirma algo que estaba en duda: **el versionado
del bucket sí quedó activado**, la SCP del laboratorio no lo denegó. El estado
tiene historial, que es una red de seguridad si un `apply` lo corrompe.

### Lo que esta prueba no cubre

El profesor lo levantará en **otra cuenta de AWS**; aquí se probó en la misma. Lo
que queda sin probar es que los nombres no choquen con recursos ajenos y que el
`LabRole` exista allí — en otra cuenta de AWS Academy existe igual (ADR 0015). Lo
que sí quedó probado es el punto 3, que es el que sostiene todo el versionado: si
nadie edita un `.tf`, la etiqueta significa lo que dice.

## Limpieza

El bucket de la prueba no se destruye con Terraform, porque Terraform nunca lo
gestionó: lo crea el script de bootstrap con la CLI (ver ADR 0013).

Y no basta con `aws s3 rm --recursive`: el bucket tiene **versionado**, así que
eso borra la versión actual de cada objeto y deja las anteriores. El
`delete-bucket` falla entonces con `BucketNotEmpty`. Hay que borrar todas las
versiones y todos los marcadores de borrado:

```bash
BUCKET=boutique-tfstate-prueba-01

for tipo in Versions DeleteMarkers; do
  while true; do
    JSON=$(aws s3api list-object-versions --bucket "$BUCKET" --max-items 500 \
      --query "{Objects: ${tipo}[].{Key:Key,VersionId:VersionId}}" --output json)
    echo "$JSON" | grep -q '"Key"' || break
    aws s3api delete-objects --bucket "$BUCKET" --delete "$JSON" >/dev/null
  done
done

aws s3api delete-bucket --bucket "$BUCKET"
```

El bucle hace falta porque `list-object-versions` pagina: con muchos objetos, una
sola pasada no los ve todos.

Y la carpeta del clon de prueba se puede borrar.
