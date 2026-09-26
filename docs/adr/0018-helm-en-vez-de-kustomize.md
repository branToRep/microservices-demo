# 0018 · El despliegue pasa a un Helm Chart propio

- **Estado:** aceptada
- **Issues:** el ticket de la v2.2.0

## Contexto
Hasta la v2.1.0 la tienda se desplegaba con Kustomize (`kubectl apply -k`) y el
pipeline actualizaba imagenes con `kubectl set image`. Funcionaba: la v2.0.0 lo
demostro en vivo.

Dos cosas obligan a cambiarlo.

**La rubrica de la materia** pide, literalmente, desplegar «mediante un Helm
Chart personalizado». No es una sugerencia de herramienta, es el entregable.

**Y lo que viene despues.** El plan incluye Vault, y posiblemente mas
herramientas de seguridad. Todo ese ecosistema —Vault, cert-manager,
external-secrets, kyverno— **se distribuye como charts de Helm**, no hay version
Kustomize oficial de ninguno. Con Kustomize habria que usar Helm igual para
esos (dos formas de desplegar) o renderizarlos a YAML y congelar su version.
Helm ademas tiene `dependencies` en `Chart.yaml`, asi que Vault puede entrar como
subchart apagable por bandera; Kustomize no tiene ese concepto.

## Decision
`charts/boutique/`, chart propio. **No** el `helm-chart/` que trae el
repositorio de Google: ese tiene 2673 lineas, esta orientado a GCP y no conoce
nuestro `wishlistservice`.

Son 584 lineas, y la pieza central es una lista en `values.yaml`:

```yaml
servicios:
  - nombre: adservice
    puerto: 9555
    env: { PORT: "9555" }
  - nombre: wishlistservice
    propia: true        # de nuestro registro, con el SHA del commit
```

Diez de los catorce deployments tienen forma identica —Deployment, Service
ClusterIP, ServiceAccount, sonda gRPC— asi que salen de **una** plantilla en vez
de diez archivos de noventa lineas casi iguales. `frontend` (sonda HTTP, dos
Service, NodePort fijo), los dos Redis y el `loadgenerator` van aparte porque de
verdad son distintos.

El pipeline pasa a `helm upgrade --install --atomic`, con la etiqueta de imagen
como parametro.

## Como se comprobo que la migracion no cambia nada
`helm lint` paso y `helm template` renderizo sin errores, **y eso no basta**. Se
comparo objeto por objeto la salida del chart contra los manifiestos: inventario,
imagenes, puertos de contenedor y de Service, variables de entorno, recursos,
sondas con sus tiempos, serviceAccounts, securityContext y selectores.

La primera comparacion encontro **dos errores que habrian roto la tienda**, los
dos invisibles para `helm lint`:

- El Service de `emailservice` expone el puerto **5000** y escucha en 8080.
  Asumir que coinciden dejaba a `checkoutservice` —que busca `emailservice:5000`—
  sin poder llamarlo.
- Al frontend le faltaba `SHOPPING_ASSISTANT_SERVICE_ADDR`. Ese servicio no se
  despliega, pero `main.go` la lee con `mustMapEnv`, que entra en panico si falta:
  el frontend no habria arrancado.

Y dieciocho diferencias de tiempos de sonda, por homogeneizarlos en el bucle
cuando los manifiestos los tenian variados. No rompian nada, y se corrigieron
igual: un chart debe reproducir lo que funciona, no lo que uno supone.

Tras las correcciones: **cero diferencias en los 38 objetos**.

La leccion, que vale mas que el chart: lo que encontro los errores fue comparar
contra la verdad conocida, no validar contra un esquema.

## Alternativas descartadas
- **Seguir con Kustomize.** Como ingenieria pura, para catorce servicios y un
  entorno, es defendible y quizas hasta preferible: no hay capa de plantillas que
  ocultar y no hay estado en el cluster. Se descarta por la rubrica y por Vault.
- **Adaptar el `helm-chart/` de Google.** Menos trabajo inmediato, pero
  «personalizado» quedaria discutible y el portafolio tendria que explicar 2673
  lineas ajenas.
- **Borrar los manifiestos.** Se conservan: son la referencia legible y la que
  permite `git diff` contra upstream. Lo que se hizo fue quitar
  `wishlistservice.yaml` de la lista del `kustomization` y poner una advertencia
  en su cabecera, para que nadie despliegue medio proyecto por ese camino.

## Consecuencias
- **Hace falta Helm instalado.** Eso rompe parte de la promesa de la v1.5.0:
  antes `kubectl apply -k` no pedia nada extra. `levantar.sh` lo comprueba y lo
  dice, y `docs/PRUEBA-CLON-LIMPIO.md` queda actualizado.
- **Ya no se lee el YAML que se aplica**, se leen plantillas. Hay que correr
  `helm template` para ver el resultado — y ahi es donde se colaron los dos
  errores de arriba.
- **Helm guarda estado en el cluster** (un Secret con la release). Si alguien
  aplica por encima con kubectl, Helm no se entera. De ahi la advertencia en el
  `kustomization`.
- A cambio: `helm rollback` revierte la release entera a una revision con
  nombre, y `--atomic` lo hace solo si un despliegue no cuaja. El
  `kubectl rollout undo` anterior revertia deployment por deployment, asi que un
  fallo a medias podia dejar el frontend nuevo hablando con un
  `wishlistservice` viejo.
