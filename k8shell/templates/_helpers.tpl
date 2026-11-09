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
{{- if and .Values.imageRegistry.host .Values.imageRegistry.existingSecret }}
imagePullSecrets:
- name: {{ .Values.imageRegistry.existingSecret }}
{{- else if and .Values.imageRegistry.host .Values.imageRegistry.username .Values.imageRegistry.password }}
imagePullSecrets:
- name: {{ printf "%s-regcred" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}


{{/*
PostgreSQL mode: simple (single instance run by the chart), cnpg
(CloudNativePG Cluster) or external (nothing installed).
*/}}
{{- define "k8shell.postgresqlMode" -}}
{{- $mode := .Values.postgresql.mode | default "simple" -}}
{{- if not (has $mode (list "simple" "cnpg" "external")) -}}
{{- fail (printf "postgresql.mode must be simple, cnpg or external, got %q" $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end }}

{{/*
secretKeyRef of a secret field ({value} or {secretName, secretKey}) for a
container env variable whose name differs from the key in the chart's int-*
Secret. Usage: include "k8shell.secretKeyRef" (dict "secretDef" .Values.x "defaultSecret" "identity" "defaultKey" "POSTGRES_PASSWORD")
*/}}
{{- define "k8shell.secretKeyRef" -}}
secretKeyRef:
  {{- if .secretDef.secretName }}
  name: {{ .secretDef.secretName }}
  key: {{ .secretDef.secretKey }}
  {{- else }}
  name: int-{{ .defaultSecret }}
  key: {{ .defaultKey }}
  {{- end }}
{{- end }}

{{/*
Fails unless a secret field has a value or a secretName/secretKey.
Usage: include "k8shell.requireSecret" (dict "field" .Values.x "path" "x")
*/}}
{{- define "k8shell.requireSecret" -}}
{{- $f := .field | default dict -}}
{{- if not (or $f.value (and $f.secretName $f.secretKey)) -}}
{{- fail (printf "%s is required: set %s.value or %s.secretName and %s.secretKey" .path .path .path .path) -}}
{{- end -}}
{{- end }}

{{/*
Identity providers installed with the chart: list of dicts with name, port
and git (backed by a git forge). Rendered as JSON.
*/}}
{{- define "k8shell.idps" -}}
{{- $idps := list -}}
{{- if .Values.idpGithub.enabled -}}
{{- $idps = append $idps (dict "name" "idp-github" "port" 9030 "git" true) -}}
{{- end -}}
{{- if .Values.idpGoogle.enabled -}}
{{- $idps = append $idps (dict "name" "idp-google" "port" 9031 "git" false) -}}
{{- end -}}
{{- toJson $idps -}}
{{- end }}

{{/*
true if a git identity provider is installed (adds the git-blueprints ConfigMap)
*/}}
{{- define "k8shell.gitIdpEnabled" -}}
{{- if .Values.idpGithub.enabled }}true{{ end -}}
{{- end }}

{{/*
Name of the ConfigMap with the infra versions api-server shows: the value of
apiServer.infraVersionsConfigMap, else the chart's k8shell-infra-versions when
the chart installs PostgreSQL or NATS, else empty.
*/}}
{{- define "k8shell.infraVersionsConfigMap" -}}
{{- if .Values.apiServer.infraVersionsConfigMap -}}
{{- .Values.apiServer.infraVersionsConfigMap -}}
{{- else if or (and .Values.postgresql.enabled (ne (include "k8shell.postgresqlMode" .) "external")) .Values.nats.install -}}
k8shell-infra-versions
{{- end -}}
{{- end }}

{{/*
Additional blueprint ConfigMaps mounted into the provisioner: the
git-blueprints of a git identity provider, then provisioner.blueprintFilesConfigMaps.
Rendered as JSON.
*/}}
{{- define "k8shell.blueprintFilesConfigMaps" -}}
{{- $cms := list -}}
{{- if include "k8shell.gitIdpEnabled" . -}}
{{- $cms = append $cms "git-blueprints" -}}
{{- end -}}
{{- toJson (concat $cms (.Values.provisioner.blueprintFilesConfigMaps | default list) | uniq) -}}
{{- end }}
