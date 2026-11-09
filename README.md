[![k8shell chart](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml)
[![k8shell-bundle chart](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell-bundle.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell-bundle.yaml)
[![idp-github chart](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-github.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-github.yaml)
[![idp-gitlab chart](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-gitlab.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-gitlab.yaml)
[![idp-google chart](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-google.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-google.yaml)
[![worktrace-detector chart](https://github.com/k8shell-io/charts/actions/workflows/chart-worktrace-detector.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-worktrace-detector.yaml)
[![vault-secrets chart](https://github.com/k8shell-io/charts/actions/workflows/chart-vault-secrets.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-vault-secrets.yaml)

# charts

Helm charts for [k8shell](https://k8shell.io) — Cloud-native Development Environment.

## Charts

| Chart | Description |
|-------|-------------|
| [k8shell](./k8shell) | The k8shell platform in one chart (2.x): the services (ssh-proxy, identity, provisioner, authz, api-server, session, frontend, sshShield), PostgreSQL (single instance, CloudNativePG cluster or external), NATS, the GitHub and Google identity providers, default authz policies and blueprints. |
| [k8shell-bundle](./k8shell-bundle) | Umbrella chart deploying k8shell 1.x together with PostgreSQL, NATS, and Vault-backed secrets as ArgoCD Applications. Frozen at 0.7.x, replaced by k8shell 2.x. |
| [idp-github](./idp-github) | GitHub Identity Provider — authenticates users via GitHub OAuth. |
| [idp-gitlab](./idp-gitlab) | GitLab Identity Provider — authenticates users via GitLab OAuth. |
| [idp-google](./idp-google) | Google Identity Provider — authenticates users via Google OAuth (Workspace and optionally personal accounts). |
| [vault-secrets](./vault-secrets) | Maps HashiCorp Vault secrets to Kubernetes secrets. |
| [worktrace-detector](./worktrace-detector) | Worktrace threat detection engine — runs as a DaemonSet and evaluates Tetragon events against detection rules. |

`k8shell-bundle`, `idp-github`, `idp-gitlab`, and `idp-google` are available under the [Early Access Program](https://docs.k8shell.io/licensing#early-access).

## Requirements

- Helm v3+
- kubectl configured against a running cluster

## Quickstart

```bash
./bin/quickstart.sh
```

Installs k8shell into your cluster with sensible defaults. Run with `--help` for available options.

See [k8shell documentation](https://docs.k8shell.io) for full configuration reference.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).

