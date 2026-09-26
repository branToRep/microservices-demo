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
{{- define "boutique.imagen" -}}
{{- if .servicio.propia -}}
{{ .raiz.Values.imagenes.nuestro.registro }}/{{ .servicio.nombre }}:{{ .raiz.Values.imagenes.nuestro.etiqueta }}
{{- else -}}
{{ .raiz.Values.imagenes.google.registro }}/{{ .servicio.nombre }}:{{ .raiz.Values.imagenes.google.etiqueta }}
{{- end -}}
{{- end -}}
