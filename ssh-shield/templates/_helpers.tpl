{{- define "ssh-shield.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ssh-shield.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ssh-shield.labels" -}}
helm.sh/chart: {{ include "ssh-shield.chart" . }}
{{ include "ssh-shield.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "ssh-shield.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ssh-shield.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Render Secret data entries from a key/value dict
*/}}
{{- define "ssh-shield.secretData" -}}
{{- range $key, $value := . }}
{{ $key }}: {{ $value | b64enc }}
{{- end }}
{{- end }}

{{/*
Name of the secret holding the NATS password
*/}}
{{- define "ssh-shield.natsPasswordSecretName" -}}
{{- if .Values.nats.password.secretName -}}
{{ .Values.nats.password.secretName }}
{{- else -}}
int-ssh-shield
{{- end }}
{{- end }}

{{/*
Key within the NATS password secret
*/}}
{{- define "ssh-shield.natsPasswordSecretKey" -}}
{{- if .Values.nats.password.secretKey -}}
{{ .Values.nats.password.secretKey }}
{{- else -}}
sshshield_nats_token
{{- end }}
{{- end }}

{{/*
Name of the secret holding the nfgate authKey
*/}}
{{- define "ssh-shield.nfgateAuthKeySecretName" -}}
{{- $nfgate := get .Values.plugins "nfgate" | default dict -}}
{{- if $nfgate.authKey.secretName -}}
{{ $nfgate.authKey.secretName }}
{{- else -}}
int-ssh-shield
{{- end }}
{{- end }}

{{/*
Key within the nfgate authKey secret
*/}}
{{- define "ssh-shield.nfgateAuthKeySecretKey" -}}
{{- $nfgate := get .Values.plugins "nfgate" | default dict -}}
{{- if $nfgate.authKey.secretKey -}}
{{ $nfgate.authKey.secretKey }}
{{- else -}}
nfgate_authkey
{{- end }}
{{- end }}

{{/*
Add imagePullSecrets
*/}}
{{- define "ssh-shield.imagePullSecrets" -}}
{{- if .Values.imageRegistry.existingSecret }}
imagePullSecrets:
- name: {{ .Values.imageRegistry.existingSecret }}
{{- else if and .Values.imageRegistry.username .Values.imageRegistry.password }}
imagePullSecrets:
- name: {{ printf "%s-regcred" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
