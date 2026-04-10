{{/*
Expand the name of the chart.
*/}}
{{- define "k8shell.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "k8shell.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "k8shell.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "k8shell.labels" -}}
helm.sh/chart: {{ include "k8shell.chart" . }}
{{ include "k8shell.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "k8shell.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8shell.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Add env variable from secret 
*/}}
{{- define "k8shell.secretEnv" -}}
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
{{- define "k8shell.secretData" -}}
{{- range $key, $value := . }}
{{ $key }}: {{ $value | b64enc }}
{{- end }}
{{- end }}

{{/* 
Add imagePullSecrets
*/}}
{{- define "k8shell.imagePullSecrets" -}}
{{- if .Values.imageRegistry.existingSecret }}
imagePullSecrets:
- name: {{ .Values.imageRegistry.existingSecret }}
{{- else if and .Values.imageRegistry.username .Values.imageRegistry.password }}
imagePullSecrets:
- name: {{ printf "%s-regcred" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

