{{/*
Etiquetas comunes a todo. 'app' es la que usan los selectores de los Service y
la que permite "kubectl get pods -l app=wishlistservice"; las otras son las
recomendadas por Kubernetes para saber de donde salio un objeto.
*/}}
{{- define "boutique.etiquetas" -}}
app.kubernetes.io/name: {{ .nombre }}
app.kubernetes.io/part-of: boutique
app.kubernetes.io/managed-by: {{ .raiz.Release.Service }}
helm.sh/chart: {{ .raiz.Chart.Name }}-{{ .raiz.Chart.Version }}
{{- end -}}

{{/*
La imagen de un servicio. Si lleva 'propia: true' sale de nuestro registro con
la etiqueta que pase el pipeline (el SHA del commit); si no, de las imagenes
publicas de Google fijadas en values.yaml.
*/}}
{{/*
La cadena de conexion a Postgres, en UN solo sitio: la usan el userservice y el
Job de migracion, y si discreparan el Job crearia el esquema en una base y el
servicio lo buscaria en otra.

La contrasena no esta aqui: va como $(POSTGRES_PASSWORD), que Kubernetes
sustituye con la variable del mismo nombre. Quien use este ayudante TIENE que
inyectar esa variable antes en su lista de 'env', o el valor llega literal.

sslmode=disable: el trafico no sale de la VPC y entre pods no va cifrado en este
cluster. Cifrarlo exigiria certificados para Postgres y no es de esta fase.
*/}}
{{- define "boutique.urlPostgres" -}}
postgres://{{ .Values.postgres.usuario }}:$(POSTGRES_PASSWORD)@{{ .Values.postgres.servicio }}:{{ .Values.postgres.puerto }}/{{ .Values.postgres.base }}?sslmode=disable
{{- end -}}

{{- define "boutique.imagen" -}}
{{- if .servicio.propia -}}
{{ .raiz.Values.imagenes.nuestro.registro }}/{{ .servicio.nombre }}:{{ .raiz.Values.imagenes.nuestro.etiqueta }}
{{- else -}}
{{ .raiz.Values.imagenes.google.registro }}/{{ .servicio.nombre }}:{{ .raiz.Values.imagenes.google.etiqueta }}
{{- end -}}
{{- end -}}
