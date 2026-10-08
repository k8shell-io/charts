{{- define "worktrace-detector.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "worktrace-detector.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "worktrace-detector.labels" -}}
helm.sh/chart: {{ include "worktrace-detector.chart" . }}
{{ include "worktrace-detector.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "worktrace-detector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "worktrace-detector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Add imagePullSecrets
*/}}
{{- define "worktrace-detector.imagePullSecrets" -}}
{{- if and .Values.imageRegistry.host .Values.imageRegistry.existingSecret }}
imagePullSecrets:
- name: {{ .Values.imageRegistry.existingSecret }}
{{- else if and .Values.imageRegistry.host .Values.imageRegistry.username .Values.imageRegistry.password }}
imagePullSecrets:
- name: {{ printf "%s-regcred" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
