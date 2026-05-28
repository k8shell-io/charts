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
