{{/*
Render the syncPolicy block for ArgoCD Application resources.
Usage: {{- include "k8shell-bundle.syncPolicy" (dict "root" . "syncOptions" (list "CreateNamespace=true")) }}
*/}}
{{- define "k8shell-bundle.syncPolicy" -}}
syncPolicy:
  {{- if .root.Values.syncPolicy.automated }}
  automated:
    prune: true
    selfHeal: true
  {{- end }}
  {{- if .syncOptions }}
  syncOptions:
  {{- range .syncOptions }}
  - {{ . }}
  {{- end }}
  {{- end }}
{{- end }}

{{/*
Postgres deployment mode: "bitnami" (default, single primary StatefulSet) or "cnpg" (CloudNativePG cluster).
The CloudNativePG operator must already be installed in the cluster for "cnpg".
*/}}
{{- define "k8shell-bundle.postgresqlMode" -}}
{{- $mode := .Values.postgresql.mode | default "bitnami" -}}
{{- if not (has $mode (list "bitnami" "cnpg")) -}}
{{- fail (printf "postgresql.mode must be \"bitnami\" or \"cnpg\", got %q" $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end }}
