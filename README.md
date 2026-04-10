[![k8shell chart](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml)

# charts

Helm charts for [k8shell](https://k8shell.io) — Cloud-native Development Environment.

## Charts

| Chart | Description |
|-------|-------------|
| [k8shell](./k8shell) | Core k8shell platform — open-source components (ssh-proxy, identity, provisioner) plus extended services (api-server, session, frontend). |

## Requirements

- Helm v3+
- kubectl configured against a running cluster

## Quickstart

```bash
./bin/quickstart.sh
```

Installs k8shell into your cluster with sensible defaults. Run with `--help` for available options.

See [k8shell documentation](https://docs.k8shell.io) for full configuration reference.
