# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Lint a chart
helm lint <chart>/

# Package a chart locally
helm package <chart>/ -d dist/

# Template a chart to inspect rendered manifests
helm template <release-name> <chart>/ -f <chart>/values.yaml

# Validate values against schema
helm lint <chart>/ --strict

# Install/upgrade from the OCI registry
helm install k8shell oci://ghcr.io/k8shell-io/charts/k8shell --namespace k8shell-system --create-namespace

# Quickstart (generates keys, creates namespace, runs helm install)
./bin/quickstart.sh --help
```

## Repository Structure

Each top-level directory is an independent Helm chart published to `oci://ghcr.io/k8shell-io/charts/<name>`.

| Chart | Role |
|-------|------|
| `k8shell` | Core platform — the primary chart users install |
| `k8shell-bundle` | Umbrella chart; wraps all charts as ArgoCD `Application` objects |
| `idp-github` / `idp-gitlab` | External identity providers; plugged into k8shell via `identity.remoteProviders` |
| `ssh-shield` | Standalone SSH brute-force protection service |
| `vault-secrets` | Maps HashiCorp Vault secrets to Kubernetes Secrets |

## k8shell Chart Architecture

The k8shell chart deploys two tiers of services:

**Core (always enabled):** `ssh-proxy`, `identity`, `provisioner`, `authz`

**Extended (disabled by default, enabled in k8shell-bundle):** `api-server`, `session`, `frontend`

**External dependencies (disabled by default):** `postgresql`, `nats` — toggled via `postgresql.enabled` / `nats.enabled`.

Service-to-service communication is gRPC. When `certManager.enabled: true`, every service gets a cert-manager-issued TLS certificate and the chart wires mTLS automatically. Without cert-manager, services fall back to plaintext.

JWT auth (`authEnabled: true`) is enforced across all gRPC endpoints. The `identity` service issues tokens signed with the key at `identity.jwtIssuer.privateKey`.

### authz service

`authz` (disabled by default, `authz.enabled: false`) is an OPA-based authorization sidecar on gRPC port 9011. It accepts requests from `ssh-proxy`, `provisioner`, `api-server`, and `identity`. Policies are either mounted from a ConfigMap (`authz.policiesConfigMap`) or fall back to the inline `authz.defaultPolicy` Rego rule. It shares the JWT private key with `identity`.

### Blueprints

`provisioner` mounts workspace blueprint YAML from `k8shell/files/blueprints/` (`base.yaml` always; `samples.yaml` when `provisioner.includeBlueprintSamples: true`). Extra blueprints can be injected via `provisioner.blueprintFilesConfigMaps`. When an IDP chart is enabled in k8shell-bundle, a `git-blueprints` ConfigMap is automatically appended to that list.

## k8shell-bundle Architecture

k8shell-bundle deploys every chart as an ArgoCD `Application` resource, all pointing at OCI chart versions pinned in `values.yaml` under `charts.*`. The bundle's `app-k8shell.yaml` template merges identity providers into `identity.remoteProviders` and blueprint ConfigMaps into `provisioner.blueprintFilesConfigMaps` automatically based on which IDP apps are enabled.

## Secret / Credentials Pattern

Throughout all charts, sensitive fields use a consistent two-option pattern:

- `field.value` — chart creates a Kubernetes Secret from the literal value.
- `field.secretName` + `field.secretKey` — chart references an existing Kubernetes Secret.

An empty `{}` on a required field signals that one of the two options must be provided.

## CI / Versioning

Each chart has its own workflow (`chart-<name>.yaml`). On a pull request the version is suffixed: `<base>-pr-<number>-<short-sha>`. On a tag push (`v*-<chart-name>`) it publishes the version from `Chart.yaml` as-is. Charts are pushed to the OCI registry configured via `secrets.REGISTRY_EXT`.

The chart `version` and `appVersion` are kept in sync in each `Chart.yaml`.

## values-internal.yaml

Each chart carries a `values-internal.yaml` alongside the public `values.yaml`. This file holds environment-specific overrides used in internal deployments and is not intended for end-users.
