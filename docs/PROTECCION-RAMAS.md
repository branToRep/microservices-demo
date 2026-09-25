# Protección de `main`

Borrar una rama ya fusionada no destruye nada: los commits viven en la historia
de `main`. Lo que sí destruye historia es un **`push --force` sobre `main`**, que
reescribe commits que otros ya tienen, y **borrar `main`**. Contra eso no hay
`git revert` que valga: lo que se reescribió deja de existir.

Este documento deja constancia de la configuración y de por qué es esa.

## La configuración

```bash
gh api -X PUT repos/branToRep/microservices-demo/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Formato y sintaxis"]
  },
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "enforce_admins": false,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true,
  "required_conversation_resolution": false
}
JSON
```

## Qué hace cada línea, y por qué

| Ajuste | Efecto | Por qué así |
|---|---|---|
| `allow_force_pushes: false` | nadie reescribe la historia de `main` | **el candado que de verdad importa**; es lo único irreversible |
| `allow_deletions: false` | no se puede borrar `main` | por si acaso |
| `contexts: ["Formato y sintaxis"]` | el PR no se fusiona si el CI falla | el trabajo que no necesita credenciales de AWS |
| `strict: true` | la rama tiene que estar al día con `main` antes de fusionar | evita fusionar contra un `main` viejo, que es lo que arrastraba trabajo ajeno |
| `required_approving_review_count: 0` | exige PR, **no** exige aprobación | somos dos y no siempre coincidimos; exigir aprobación pararía el proyecto |
| `required_linear_history: true` | solo squash o rebase, sin commits de merge | es lo que mantiene `main` en un commit por ticket |
| `enforce_admins: false` | quien administra puede saltárselo | valvula de escape para desatascar algo sin pelear con la configuración |

La decisión discutible es la de las aprobaciones. Lo correcto en un equipo de
verdad es exigir una, y el proyecto lo soporta sin cambiar nada más: basta subir
ese `0` a `1`. Aquí está en cero porque somos dos estudiantes con horarios
distintos, y un PR bloqueado esperando a que el otro se conecte no ensena nada
sobre CI/CD; solo retrasa.

Lo que **no** se protege, a proposito:

- **Las etiquetas.** `git push origin v1.4.0` sigue funcionando. Una etiqueta ya
  publicada no se mueve por convencion (ver `docs/VERSIONADO.md`), no por
  configuracion.
- **Las ramas de trabajo.** `feat/NN-slug` se reescribe y se borra libremente
  mientras no este fusionada. Es donde tiene sentido experimentar.

## Estado actual: aplicada

El comando de arriba devuelve **404** si lo corre quien no administra el
repositorio. GitHub responde 404 en vez de 403 para no revelar si el recurso
existe, así que el error no dice la causa real. Se averigua así:

```bash
gh api repos/branToRep/microservices-demo \
  --jq '{privado: .private, mis_permisos: .permissions}'
```

En este proyecto sale:

```json
{ "mis_permisos": { "admin": false, "push": true, "triage": true },
  "privado": false }
```

Es decir: **falta permiso de administración**, no falta plan. El repositorio es
público, y en repositorios públicos la protección de ramas está disponible en el
plan gratuito. El fork pertenece a `branToRep` y el resto del equipo entra como
colaborador con `push`, que alcanza para ramas y PR pero no para configurar la
rama por defecto.

### Quién puede aplicarla

- `branToRep`, corriendo el bloque de arriba tal cual.
- O cualquiera a quien suba a **Admin** en Settings → Collaborators.

### Aplicada el 25 de septiembre de 2026

La aplicó `branToRep` desde **Settings → Branches** en la web, que es el mismo
conjunto de ajustes que el JSON de arriba, casilla por casilla. La regla ya
existía a medias de un intento anterior, y de ahí el mensaje
`name already protected: main` al intentar crear una segunda: en ese caso se
**edita** la existente, no se crea otra.

Comprobable sin permiso de administración:

```bash
gh api repos/branToRep/microservices-demo/branches/main --jq '.protected'
```

Efecto inmediato en el dia a dia: **ya no se puede hacer `git push` directo a
`main`**. Todo commit pasa por PR. Las etiquetas siguen subiendose normal
(`git push origin v1.5.0` no toca la rama).

El archivo `docs/proteccion-main.json` queda versionado para poder reaplicar la
misma configuración en otro repositorio, o restaurarla si alguien la cambia:

```bash
gh api -X PUT repos/branToRep/microservices-demo/branches/main/protection \
  --input docs/proteccion-main.json
```

### Qué riesgo quedaba mientras no estuvo

Uno solo, y era el importante: nada impedía técnicamente un `push --force` sobre
`main`. Lo único que lo evitaba era convención, no configuración — y una
convención no detiene un comando escrito por error. Queda escrito porque durante
cuatro versiones (de la 1.0.0 a la 1.4.0) ese agujero estuvo abierto.

Lo que sí sigue en pie sin protección:

- Todo el trabajo pasa por PR, porque es el flujo del proyecto.
- El CI corre igual en cada PR que toque `infra/`; lo que falta es que su
  resultado **impida** fusionar.
- Las etiquetas publicadas son el registro fiel: si alguien reescribiera `main`,
  `git checkout v1.4.1` seguiría devolviendo el código de esa versión.

Por eso esto se documenta en vez de quedarse en el aire: la configuración es
una línea de trabajo del repositorio igual que el código, y quien tenga los
permisos puede aplicarla sin averiguar nada.

## Comprobarlo

```bash
gh api repos/branToRep/microservices-demo/branches/main/protection \
  --jq '{
    force_push: .allow_force_pushes.enabled,
    borrado:    .allow_deletions.enabled,
    checks:     .required_status_checks.contexts,
    lineal:     .required_linear_history.enabled
  }'
```

Los dos primeros tienen que salir `false`.

## Si el nombre del check no coincide

`contexts` espera el nombre del **trabajo**, no del flujo. Si la proteccion no
llega a exigir nada, mira como se llama de verdad en el ultimo commit:

```bash
gh api repos/branToRep/microservices-demo/commits/main/check-runs --jq '.check_runs[].name'
```

y pon ese nombre exacto.
