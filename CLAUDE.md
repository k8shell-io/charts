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
| `k8shell` | The whole platform in one chart (2.x): services, PostgreSQL, NATS (subchart), idp-github/idp-google, default policies and blueprints |
| `k8shell-bundle` | Umbrella chart for k8shell 1.x; wraps all charts as ArgoCD `Application` objects. Frozen at 0.7.x, replaced by k8shell 2.x |
| `idp-github` / `idp-gitlab` / `idp-google` | Identity providers as separate charts (used by k8shell-bundle); idp-github and idp-google are also part of the k8shell chart since 2.0 |
| `vault-secrets` | Maps HashiCorp Vault secrets to Kubernetes Secrets |
| `worktrace-detector` | Threat detection engine; DaemonSet consuming Tetragon events (needs Tetragon installed). Ships no rules: a leader-elected `controller` Deployment reads them from an externally provided ConfigMap (`rules.configMap`), serves them to the detectors and generates the TracingPolicy from them |

## k8shell Chart Architecture

The k8shell chart deploys two tiers of services:

**Core (always enabled):** `ssh-proxy`, `identity`, `provisioner`, `authz`

**Extended (enabled by default since 2.0):** `api-server`, `session`, `frontend`, `authz`

**Optional (disabled by default, opt-in even in k8shell-bundle):** `sshShield`

**Infrastructure (installed by default since 2.0):**
- `postgresql` — `postgresql.mode`: `simple` (a single-instance StatefulSet `db-postgresql`, official postgres image, PVC kept on uninstall), `cnpg` (a CloudNativePG `Cluster` `db-postgresql`, operator required) or `external`. The Service `db-postgresql` points at the primary in both installed modes.
- `nats` — `nats.install` adds the official NATS chart as the subchart `natsServer` (values under `natsServer`, `fullnameOverride: nats`). `nats.enabled` still means "the services use NATS"; `templates/validate.yaml` checks that the NATS server reads the same password Secret as the services.
- `k8shell-infra-versions` ConfigMap (versions of the installed PostgreSQL/NATS for api-server) is created automatically.

**Organizations and roles:** identity has no built-in organization. `identity.organizations` (name, description, nodeSelectors, organization-scoped roles) and `identity.roles` (global roles besides the built-in `admin` and `org-admin`; defaults `developer`, `git-workspace`) are rendered into identity's config and created at startup if missing; node selectors are set only while an organization has none. Every entry of `identity.users` needs an `organization` declared there (`templates/validate.yaml`) and gets an onboarding rule with its organization, roles and sudo.

**Identity providers (disabled by default):** `idpGithub`, `idpGoogle` — templates in `templates/idp-github/`, `templates/idp-google/`, using the chart's shared settings (certManager, grpc, authEnabled, imageRegistry, nats, postgresql). Enabled providers are appended to `identity.remoteProviders`; idpGithub also adds the `git-blueprints` ConfigMap (`files/git-blueprints/`) and makes `git-dev` the default custom blueprint.

Service-to-service communication is gRPC. When `certManager.enabled: true`, every service gets a cert-manager-issued TLS certificate and the chart wires mTLS automatically. Without cert-manager, services fall back to plaintext.

JWT auth (`authEnabled: true`) is enforced across all gRPC endpoints. The `identity` service issues tokens signed with the key at `identity.jwtIssuer.privateKey`.

### authz service

`authz` (disabled by default, `authz.enabled: false`) is an OPA-based authorization sidecar on gRPC port 9011. It accepts requests from `ssh-proxy`, `provisioner`, `api-server`, and `identity`. The chart ships default policies (`files/policies/*.rego`, ConfigMap `authz-policies-default`); they hold no site-specific settings, permissions follow from roles (`admin`, `org-admin`, `<group>-admin`, `developer` for inject mode, `git-workspace` for repositories). `authz.policiesConfigMap` replaces the whole set with an external ConfigMap. `authz.defaultPolicy` is the inline rule used when no policy file matches. Policy tests: `k8shell/policy-tests/run.sh` (needs opa, jq). It shares the JWT private key with `identity`.

### sshShield service

`sshShield` (disabled by default, `sshShield.enabled: false`) provides SSH brute-force protection. It consumes SSH failure events over the shared `nats` (published by `ssh-proxy` when `sshProxy.publishSshFailures.enabled: true`, subject must match `sshShield.sshFailures.subject`) and bans offending IPs via a pluggable blocker backend (e.g. the `nfgate` plugin). It requires `nats.enabled: true`. It also exposes a gRPC server on port 9040, gated the same way as other services by `certManager.enabled` (TLS) and `authEnabled` (JWT, restricted to the `api-server` service account).

### Blueprints

`provisioner` mounts workspace blueprint YAML from `k8shell/files/blueprints/` (`base.yaml` always; `samples.yaml` when `provisioner.includeBlueprintSamples: true`) as the ConfigMap `blueprint-base-files`; `provisioner.blueprintsConfigMap` replaces it with an external ConfigMap. Extra blueprints are added via `provisioner.blueprintFilesConfigMaps` (file names unique across ConfigMaps, blueprint names unique across files). With idpGithub enabled, `git-blueprints` is appended automatically.

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
