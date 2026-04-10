# charts

[![Build k8shell chart](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml/badge.svg)](https://github.com/k8shell-io/charts/actions/workflows/chart-k8shell.yaml)

Helm charts for [k8shell](https://k8shell.io) — a Kubernetes-native browser-based SSH terminal.

## Charts

| Chart | Description |
|-------|-------------|
| [k8shell](./k8shell) | Core k8shell platform (SSH proxy, identity, provisioner, session, frontend) |

## Quickstart

```bash
./bin/quickstart.sh
```

Installs k8shell into your cluster with sensible defaults. Run with `--help` for available options.

## Requirements

- Helm v3+
- kubectl configured against a running cluster

## Installation

```bash
helm install k8shell oci://registry.k8shell.io/charts/k8shell \
  --version <version> \
  --namespace k8shell-system \
  --create-namespace
```

See [k8shell documentation](https://docs.k8shell.io) for full configuration reference.
