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

{{/*
Rules the provisioner needs inside a workspace namespace: the target namespace
(Role provisioner), every organization namespace (ClusterRole
provisioner-workspaces-<release namespace>, bound there by the provisioner) or,
with organizations off, the single organization's namespace (Role
provisioner-workspaces). Only what it uses, and all within Kubernetes'
built-in "admin" role, so that a namespace admin can install k8shell with
organizations off. Two exceptions are optional for that reason: the quota rules
(k8shell.provisionerQuotaRules, organizations.defaultNamespace.quota) and
in-place resize (provisioner.liveResize). CiliumNetworkPolicies are a third on
clusters where Cilium doesn't aggregate them into "admin".
*/}}
{{- define "k8shell.provisionerWorkspaceRules" }}
  # workspaces (the workspace chart's pods, PVCs, secrets, config maps,
  # services), their shells and logs, and Helm's release secrets
  - apiGroups: [""]
    resources:
      [
        "pods",
        "pods/exec",
        "pods/attach",
        "pods/portforward",
        "pods/proxy",
        "configmaps",
        "persistentvolumeclaims",
        "secrets",
        "services",
        "services/proxy",
        "serviceaccounts",
      ]
    verbs:
      [
        "create",
        "delete",
        "deletecollection",
        "get",
        "list",
        "patch",
        "update",
        "watch",
      ]
  - apiGroups: [""]
    resources: ["pods/log", "events", "endpoints"]
    verbs: ["get", "list", "watch"]
{{- if ne (toString .Values.provisioner.liveResize) "false" }}
  # in-place resize (provisioner.liveResize; beyond Kubernetes' built-in
  # "admin" role)
  - apiGroups: [""]
    resources: ["pods/resize"]
    verbs: ["get", "patch", "update"]
{{- end }}
  # workspace usage
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create", "get", "list", "delete", "watch", "update", "patch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs:
      ["create", "delete", "deletecollection", "get", "list", "watch", "update", "patch"]
{{- if .Capabilities.APIVersions.Has "cilium.io/v2/CiliumNetworkPolicy" }}
  - apiGroups: ["cilium.io"]
    resources: ["ciliumnetworkpolicies"]
    verbs:
      ["create", "delete", "deletecollection", "get", "list", "watch", "update", "patch"]
{{- end }}
{{- if .Values.certManager.enabled }}
  - apiGroups: ["cert-manager.io"]
    resources:
      - certificates
    verbs: ["create","get","list","watch","update","patch","delete","deletecollection"]
{{- end }}
{{- end }}

{{/*
Rules for organization quotas: the ResourceQuota and the LimitRange of
container defaults in an organization's namespace. Beyond Kubernetes'
built-in "admin" role (namespace admins may not change their own quotas).
*/}}
{{- define "k8shell.provisionerQuotaRules" }}
  - apiGroups: [""]
    resources: ["resourcequotas", "limitranges"]
    verbs: ["create", "delete", "get", "list", "watch", "update", "patch"]
{{- end }}

{{/* "true" when the single organization (organizations off) has a quota. */}}
{{- define "k8shell.singleOrgQuota" -}}
{{- $d := (.Values.organizations | default dict).defaultNamespace | default dict -}}
{{- if or (not (hasKey $d "quota")) $d.quota }}true{{ end -}}
{{- end }}

{{/* Name of the provisioner's workspace ClusterRole. */}}
{{- define "k8shell.provisionerWorkspaceClusterRole" -}}
{{- printf "provisioner-workspaces-%s" .Release.Namespace | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
With organizations off: the single organization (the only entry of
identity.organizations) and its workspace namespace
(organizations.defaultNamespace.name, default <targetNamespace>-<organization>).
*/}}
{{- define "k8shell.singleOrganization" -}}
{{- (first (.Values.identity.organizations | default (list (dict "name" "default")))).name -}}
{{- end }}

{{- define "k8shell.singleOrgNamespace" -}}
{{- $ns := ((.Values.organizations | default dict).defaultNamespace | default dict).name -}}
{{- $ns | default (printf "%s-%s" .Values.provisioner.targetNamespace (include "k8shell.singleOrganization" .)) -}}
{{- end }}

{{/* "true" when organizations are on (the default). */}}
{{- define "k8shell.organizationsEnabled" -}}
{{- $o := .Values.organizations | default dict -}}
{{- if or (not (hasKey $o "enabled")) $o.enabled }}true{{ end -}}
{{- end }}

{{/* "true" when injectNamespaces holds "*" (cluster-wide injection). */}}
{{- define "k8shell.clusterWideInjection" -}}
{{- if has "*" (.Values.provisioner.injectNamespaces | default list) }}true{{ end -}}
{{- end }}

{{/*
Rules the provisioner needs in a namespace it injects workspaces into: in a
Role per inject namespace, or a ClusterRole with injectNamespaces ["*"].
*/}}
{{- define "k8shell.provisionerInjectRules" }}
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["replicasets", "daemonsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["configmaps", "secrets", "services"]
  verbs: ["get", "create", "update", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "create"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "create", "update", "delete", "patch"]
- apiGroups: ["cert-manager.io"]
  resources: ["certificates"]
  verbs: ["get", "create", "update", "patch", "delete"]
{{- end }}

{{/*
The hostnames the installation is reached at, as a JSON list for the license
config: license.hosts, or frontend.host. A license bound to hosts must cover
all of them.
*/}}
{{- define "k8shell.licenseHosts" -}}
{{- if .Values.license.hosts -}}
{{- toJson .Values.license.hosts -}}
{{- else -}}
{{- toJson (list .Values.frontend.host) -}}
{{- end -}}
{{- end }}
