{{/*
Application name.
*/}}
{{- define "myapp-chart.name" -}}
{{- default .Chart.Name .Values.application.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Release-specific resource name.
*/}}
{{- define "myapp-chart.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "myapp-chart.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "myapp-chart.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "myapp-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "myapp-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}