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

### Quickstart for k8shell 2.x

```bash
export K8SHELL_REGISTRY_USERNAME=... K8SHELL_REGISTRY_PASSWORD=...
./bin/quickstart-v2.sh            # --dry-run to see the plan without installing
```

Installs the k8shell 2.x chart (the newest 2.x version in the registry unless
`--version` is given). It first checks what your Kubernetes user may do and
proposes a mode, which `--mode` overrides:

| Mode | When | What you get |
|---|---|---|
| `full` | you may create cluster-scoped RBAC and namespaces (cluster admin) | organizations, node pools, node usage (with metrics-server) |
| `no-cluster-rbac` | you may create namespaces, but no ClusterRoles | a single organization, no node information; the script creates the namespaces |
| `namespace-admin` | neither: existing namespaces where you have Kubernetes' built-in `admin` role | a single organization in your namespaces (by default all in your context's namespace), no node information, no organization quota or live resize unless you may grant them |

It shows the plan (mode and why, features on and off, namespaces, chart
version) and asks before installing. Keys and passwords are kept in
`~/k8shell-quickstart` (`K8SHELL_QUICKSTART_DIR`), so running it again upgrades
the same installation. Afterwards it prints how to connect with SSH (a NodePort,
default `30022`) and the web UI address: the web UI uses the cluster's
IngressClass (`--ingress-class`, default: the cluster's default class) and the
host `<node-ip>.nip.io` (`--host`); sign in as `admin` with the password in
`~/k8shell-quickstart/admin-password` (hashed with `htpasswd`, python3 `bcrypt`
or `mkpasswd`, whichever is installed).

The images and the chart come from `registry.k8shell.io` and need credentials
(`--registry-username`/`--registry-password` or the variables above);
`--registry ""` with `--chart` installs public images without credentials. On
clusters with Cilium, the restricted modes need CiliumNetworkPolicy rights in
the namespace (see below). Set passwords in single quotes
(`export K8SHELL_REGISTRY_PASSWORD='...'`): in double quotes the shell expands
a `!`.

Before installing, the script also checks, where your permissions allow it:

- that k8shell's images are published for the nodes' architectures (linux/amd64
  and linux/arm64 for release builds);
- that the cluster has a default StorageClass for the database and NATS volumes
  (on a local cluster, for example
  [local-path](https://github.com/rancher/local-path-provisioner));
- that the web UI's address answers: the IngressClass's controller must be
  reachable at `--host` (a LoadBalancer address, or hostPort 80/443 on the
  nodes; on clusters in local VMs a LoadBalancer gets no address);
- that the SSH NodePort is free;

and builds the dependencies of a local chart directory (`--chart ./k8shell`).

**Apple Silicon and other arm64 clusters.** Release builds of the images,
`k8shelld` and the default workspace images are multi-arch, so k8shell runs
natively on arm64 nodes. A local cluster needs a default StorageClass and an
ingress controller listening on the nodes, for example Traefik:

```bash
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik -n traefik --create-namespace \
  --set ingressClass.isDefaultClass=true --set deployment.kind=DaemonSet \
  --set ports.web.hostPort=80 --set ports.websecure.hostPort=443 \
  --set 'tolerations[0].key=node-role.kubernetes.io/control-plane' \
  --set 'tolerations[0].operator=Exists' --set 'tolerations[0].effect=NoSchedule'
```

See [k8shell documentation](https://docs.k8shell.io) for full configuration reference.

## Permissions and minimal installations

The k8shell chart renders cluster-scoped RBAC only for the features that need
it; there is no separate switch for it. Everything else is namespaced.

| Feature | Values | Needs, cluster-wide |
|---|---|---|
| Organizations, each with its own workspace namespace | `organizations.enabled` (default `true`) | namespaces (create, label, delete), RoleBindings and `bind` on the provisioner's workspace ClusterRole |
| Node pools and placement options | `provisioner.nodeSelectorKeys` (default: two keys) | read nodes |
| Node usage | `provisioner.nodeUsage.enabled` (default `false`) and its parts | read nodes; node metrics and other pods for the optional parts |
| Injection into every namespace | `provisioner.injectNamespaces: ["*"]` | the inject rights in every namespace (explicit namespaces get a Role in each) |

With organizations off there is a single organization, the only entry of
`identity.organizations`; it can't be deleted and no other can be added. Its
workspaces run in `organizations.defaultNamespace.name` (default
`<provisioner.targetNamespace>-<organization>`), which the chart sets up with a
Role. The UI and `GET /api/v1/features` show what is turned off.

A minimal installation, with no cluster-scoped object at all:

```yaml
organizations:
  enabled: false
  defaultNamespace:
    create: false   # the namespace exists already; true lets the chart create it (a Namespace is cluster-scoped)
provisioner:
  nodeSelectorKeys: []
  nodeUsage:
    enabled: false
```

The namespaces it uses (the release namespace, `provisioner.targetNamespace`
and the workspace namespace, which may be the target namespace) must exist.

**Installing as a namespace admin.** A user bound to Kubernetes' built-in
`admin` role in those namespaces can install the minimal installation if the
Roles it creates hold nothing beyond `admin`. Two features need more and can be
turned off for that:

```yaml
organizations:
  defaultNamespace:
    quota: false      # no organization quota (namespace admins may not change their quotas)
provisioner:
  liveResize: false   # no in-place resize (pods/resize); resources change when a workspace is provisioned again
```

On clusters with Cilium, workspaces also need CiliumNetworkPolicies, which
Cilium doesn't add to `admin` by default: a cluster admin aggregates them
first. `k8shell/rbac-tests/run.sh` checks which cluster-scoped objects each
combination renders. `bin/quickstart-v2.sh` finds out which of these
installations your permissions allow and sets the values for you.

## Hot reload in injected workspaces

A workspace can be injected into an existing workload (a Deployment,
StatefulSet or DaemonSet in a namespace listed in `provisioner.injectNamespaces`):
the provisioner adds the workspace as a sidecar to the workload's pods, so you
can work on a service next to it. To let you run a new build of the service
there without rebuilding its image or restarting the pod, the provisioner also
wraps the service container in **devrun**, a small supervisor shipped in the
k8shelld image:

- An init container copies devrun into a shared `emptyDir` mounted at
  `/devrun` in the service container and in the workspace.
- The service container's command becomes
  `/devrun/devrun run --dir /devrun -- <original command>`. The original
  command comes from the container spec, or else from the image's
  `ENTRYPOINT`/`CMD`, read from the registry with the pod's image pull
  secrets. The working directory, user and environment are unchanged, and the
  service's output still goes to `kubectl logs`.
- The container's liveness probe is removed while the workspace is injected:
  a debugger breakpoint or a reload would otherwise fail it and restart the
  container. Readiness probes stay.
- Ejecting the workspace restores the workload as it was.

In the workspace, `/devrun/devrun reload <binary>` runs a new build with the
original arguments and waits until it has kept running for two seconds (or
reports how it exited); `/devrun/devrun reload --original` goes back to the
image's binary, and `/devrun/devrun status` shows what runs. The k8shell
services wrap this in `make reload` and `make reload-original`. If a build
crashes, devrun restarts it with a backoff while the container keeps running,
and a container restart runs the last reloaded build again. Files the build
reads at startup from the image (for example database migrations) are still
the image's.

| Setting | Values |
|---|---|
| `provisioner.injectDevrun.enabled` | `true` (default): wrap the service container; `false`: inject the workspace only |
| Annotation `k8shell.io/devrun-container` on the workload | the container to wrap when the pod has several; otherwise the container named like the workload, or the first one |

When the command can't be determined (an unreachable registry, missing
credentials), the workspace is injected without devrun and the provisioning
progress shows a warning. A command that runs a shell (`sh -c ...`) is wrapped
but can't be reloaded: devrun replaces the program the container starts, so
the container must start the service binary itself. No extra RBAC is needed:
the provisioner already patches the workload and reads the pull secrets with
its inject rights.

## License limits

Without a license k8shell runs the free tier: 1 organization, 3 users and 5
workspaces per organization (stopped and injected workspaces included). A
license raises or removes these limits. Admins upload it in the app (License
page, or `PUT /api/v1/license`); identity stores it. The chart can seed it:

```yaml
license:
  token:
    value: "<license token>"        # or secretName/secretKey of an existing Secret
  force: false                      # import a changed token even if it is older than the stored license
  hosts: []                         # hostnames the installation is reached at; default frontend.host
  checkInterval: 1m
```

The token is imported once per content: when there is no license yet, or it
was issued later than the stored one (always with `force`). A license
uploaded in the app since is kept until the token changes again. A license
bound to hosts must cover every host in `license.hosts`.

At a limit a create is refused with 409 `limit_reached`; while the
installation is over any limit (for example after a license expired), no new
organization, user or workspace can be created (409 `over_limit`), but
nothing existing is locked or deleted.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).

