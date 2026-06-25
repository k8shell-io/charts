[![k8shell chart](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml)
[![k8shell-bundle chart](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell-bundle.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell-bundle.yaml)
[![idp-github chart](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-github.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-github.yaml)
[![idp-gitlab chart](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-gitlab.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-idp-gitlab.yaml)
[![ssh-shield chart](https://github.com/k8shell-io/charts/actions/workflows/chart-ssh-shield.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-ssh-shield.yaml)
[![vault-secrets chart](https://github.com/k8shell-io/charts/actions/workflows/chart-vault-secrets.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-vault-secrets.yaml)

# charts

Helm charts for [k8shell](https://k8shell.io) — Cloud-native Development Environment.

## Charts

| Chart | Description |
|-------|-------------|
| [k8shell](./k8shell) | Core k8shell platform — open-source components (ssh-proxy, identity, provisioner) plus extended services (api-server, authz, session, frontend). |
| [k8shell-bundle](./k8shell-bundle) | Umbrella chart deploying k8shell together with PostgreSQL, NATS, and Vault-backed secrets. |
| [idp-github](./idp-github) | GitHub Identity Provider — authenticates users via GitHub OAuth. |
| [idp-gitlab](./idp-gitlab) | GitLab Identity Provider — authenticates users via GitLab OAuth. |
| [ssh-shield](./ssh-shield) | SSH Shield service — policy enforcement proxy for SSH sessions. |
| [vault-secrets](./vault-secrets) | Maps HashiCorp Vault secrets to Kubernetes secrets. |

`k8shell-bundle`, `idp-github`, `idp-gitlab`, and `ssh-shield` are available under the [Early Access Program](https://docs.k8shell.io/licensing#early-access).

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

