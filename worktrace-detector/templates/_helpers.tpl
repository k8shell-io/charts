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

{{/*
Name and key of the Secret holding the NATS password: the one this chart creates
when nats.password.value is set, else the configured existing Secret.
*/}}
{{- define "worktrace-detector.natsSecretName" -}}
{{- if .Values.nats.password.value -}}
worktrace-detector-nats
{{- else if .Values.nats.password.secretName -}}
{{- .Values.nats.password.secretName -}}
{{- else -}}
{{- fail "nats.password is required (set .value or .secretName/.secretKey)" -}}
{{- end -}}
{{- end }}

{{- define "worktrace-detector.natsSecretKey" -}}
{{- if .Values.nats.password.value -}}
password
{{- else -}}
{{- required "nats.password.secretKey is required with nats.password.secretName" .Values.nats.password.secretKey -}}
{{- end -}}
{{- end }}

{{/*
Projected volume source adding the NATS password next to the projected tokens, so both
pods find it at /var/run/secrets/k8shell.io/nats-password.
*/}}
{{- define "worktrace-detector.natsPasswordSource" -}}
- secret:
    name: {{ include "worktrace-detector.natsSecretName" . }}
    items:
      - key: {{ include "worktrace-detector.natsSecretKey" . }}
        path: nats-password
{{- end }}

{{/*
Env variable from a secret definition (same as k8shell.secretEnv in the k8shell chart):
.secretDef.secretName/.secretKey reference an existing Secret; otherwise the value comes
from this chart's int-<defaultSecret> Secret, keyed by the variable name. Disabled: empty.
*/}}
{{- define "worktrace-detector.secretEnv" -}}
{{- if .enabled -}}
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
{{- else -}}
- name: {{ .name }}
  value: ""
{{- end }}
{{- end }}

{{/*
Render Secret data entries from a key/value dict (same as k8shell.secretData).
*/}}
{{- define "worktrace-detector.secretData" -}}
{{- range $key, $value := . }}
{{ $key }}: {{ $value | b64enc }}
{{- end }}
{{- end }}
