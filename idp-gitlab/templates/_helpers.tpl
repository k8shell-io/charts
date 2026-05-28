{{- define "idp-gitlab.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "idp-gitlab.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "idp-gitlab.labels" -}}
helm.sh/chart: {{ include "idp-gitlab.chart" . }}
{{ include "idp-gitlab.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "idp-gitlab.selectorLabels" -}}
app.kubernetes.io/name: {{ include "idp-gitlab.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Add env variable from secret
*/}}
{{- define "idp-gitlab.secretEnv" -}}
{{- if .enabled }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      {{- if .secretDef.secretName }}
      name: {{ .secretDef.secretName }}
      key: {{ .secretDef.secretKey }}
      {{- else }}
      name: int-{{ .defaultSecret }}
      key: {{ .name }}
      {{- end }}
{{- else }}
- name: {{ .name }}
  value: ""
{{- end }}
{{- end }}

{{/*
Render Secret data entries from a key/value dict
*/}}
{{- define "idp-gitlab.secretData" -}}
{{- range $key, $value := . }}
{{ $key }}: {{ $value | b64enc }}
{{- end }}
{{- end }}

{{/* 
Add imagePullSecrets
*/}}
{{- define "idp-gitlab.imagePullSecrets" -}}
{{- if and .Values.imageRegistry.host .Values.imageRegistry.existingSecret }}
imagePullSecrets:
- name: {{ .Values.imageRegistry.existingSecret }}
{{- else if and .Values.imageRegistry.host .Values.imageRegistry.username .Values.imageRegistry.password }}
imagePullSecrets:
- name: {{ printf "%s-regcred" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}