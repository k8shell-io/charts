#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# quickstart-v2.sh — k8shell 2.x installation helper
#
# Installs the k8shell 2.x chart into a Kubernetes cluster using Helm. Finds out
# what the current Kubernetes user may do and proposes the installation that
# fits: a full installation for a cluster admin, one without cluster-scoped
# RBAC, or one inside existing namespaces for a namespace admin. Handles
# prerequisite checks, key and password generation, namespace setup, and
# prints connection instructions on success.
#
# Version : 2.1.0
# Authors : k8shell Authors
# License : GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)
#           https://www.gnu.org/licenses/agpl-3.0.html
# Source  : https://github.com/k8shell-io/charts
# Copyright (c) 2026 k8shell Authors. All rights reserved.
set -euo pipefail

# ---------------------------------------------------------------------------
# k8shell quickstart v2
# ---------------------------------------------------------------------------

SCRIPT_VERSION="2.1.0"
# Chart major version this script installs: the newest 2.x version in the
# registry unless --version is given (Helm's own "latest" would pick the
# highest version of any series).
CHART_SERIES="2"
CHART_VERSION=""
# the public release on ghcr.io; internal installs and release tests pass
# --chart oci://registry.k8shell.io/charts/k8shell --registry registry.k8shell.io
CHART_REF="oci://ghcr.io/k8shell-io/charts/k8shell"
VALUES_FILES=()
ASSUME_YES="false"
DRY_RUN="false"
# Registry of the images (and of the chart, when the chart reference points
# there) that needs credentials. Empty (the default): public images, no
# credentials, as in the chart published on ghcr.io.
REGISTRY_HOST=""
REGISTRY_USERNAME="${K8SHELL_REGISTRY_USERNAME:-}"
REGISTRY_PASSWORD="${K8SHELL_REGISTRY_PASSWORD:-}"
MODE=""
NAMESPACE=""
TARGET_NAMESPACE=""
WORKSPACE_NAMESPACE=""
DEFAULT_NAMESPACE="k8shell-system"
DEFAULT_TARGET_NAMESPACE="k8shell-workspaces"
QUICKSTART_DIR="${K8SHELL_QUICKSTART_DIR:-$HOME/k8shell-quickstart}"
GENERATED_SSH_KEY="$QUICKSTART_DIR/admin-ssh-key"
NODE_PORT_ENABLED="true"
NODE_PORT="30022"
INGRESS_CLASS=""
WEB_HOST=""
WEB_SCHEME="https"
WEB_ENABLED="true"
WAIT_TIMEOUT="10m"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Version : $SCRIPT_VERSION
License : AGPL-3.0-or-later — https://github.com/k8shell-io/charts

Installs the k8shell ${CHART_SERIES}.x chart. It first checks what your Kubernetes user
may do and proposes one of these modes (change it with --mode):

  full             cluster admin: organizations, node pools and node usage
  no-cluster-rbac  no cluster-scoped RBAC, but namespaces can be created:
                   a single organization, no node information
  namespace-admin  existing namespaces only (Kubernetes' built-in "admin"
                   role there): a single organization, no node information,
                   no organization quota or live resize unless allowed

Options:
  -m, --mode MODE            full, no-cluster-rbac or namespace-admin
                             (default: proposed from your permissions)
  -v, --version VERSION      Helm chart version (default: the newest ${CHART_SERIES}.x)
  -c, --chart REF            Chart to install: OCI reference or local chart
                             directory (default: $CHART_REF)
  -f, --values FILE          Additional values file (repeatable), applied last
  -y, --yes                  Do not ask for confirmation
      --dry-run              Show the plan and the values, install nothing
      --registry HOST        Private registry of the images, with credentials
                             (default: none, public images from ghcr.io)
      --registry-username U  Username for the registry (or K8SHELL_REGISTRY_USERNAME)
      --registry-password P  Its password (or K8SHELL_REGISTRY_PASSWORD)
  -n, --namespace NS         k8shell release namespace (default: $DEFAULT_NAMESPACE;
                             namespace-admin: your context's namespace)
  -t, --target-namespace NS  Provisioner target namespace (default: $DEFAULT_TARGET_NAMESPACE;
                             namespace-admin: the release namespace)
  -w, --workspace-namespace NS
                             Namespace of the workspaces with a single
                             organization (default: <target namespace>-default;
                             namespace-admin: the target namespace)
      --node-port PORT       Expose SSH via NodePort (default: $NODE_PORT)
      --disable-node-port    Disable NodePort SSH service
      --ingress-class CLASS  IngressClass for the web UI (default: the cluster's
                             default class, or the only one)
      --host HOST            Host name of the web UI (default: <node-ip>.nip.io)
      --web-scheme SCHEME    https or http (default: $WEB_SCHEME)
      --disable-web          Do not set up the web UI's host and class
      --timeout DURATION     How long to wait for k8shell to start (default: $WAIT_TIMEOUT)
  -h, --help                 Show this help message

Environment:
  K8SHELL_REGISTRY_USERNAME, K8SHELL_REGISTRY_PASSWORD
                             Registry credentials (instead of the options)
  K8SHELL_QUICKSTART_DIR     Where keys and passwords are kept, so that
                             running the script again upgrades the same
                             installation (default: ~/k8shell-quickstart)

The web UI's 'admin' password is generated into <dir>/admin-password; hashing
it needs htpasswd, python3 with bcrypt, or mkpasswd.
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "[INF] $*" >&2; }
warn()  { echo "[WRN] $*" >&2; }
error() { echo "[ERR] $*" >&2; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mode)                MODE="$2"; shift 2 ;;
        -v|--version)             CHART_VERSION="$2"; shift 2 ;;
        -c|--chart)               CHART_REF="$2"; shift 2 ;;
        -f|--values)              VALUES_FILES+=("$2"); shift 2 ;;
        -y|--yes)                 ASSUME_YES="true"; shift ;;
        --dry-run)                DRY_RUN="true"; shift ;;
        --registry)               REGISTRY_HOST="$2"; shift 2 ;;
        --registry-username)      REGISTRY_USERNAME="$2"; shift 2 ;;
        --registry-password)      REGISTRY_PASSWORD="$2"; shift 2 ;;
        -n|--namespace)           NAMESPACE="$2"; shift 2 ;;
        -t|--target-namespace)    TARGET_NAMESPACE="$2"; shift 2 ;;
        -w|--workspace-namespace) WORKSPACE_NAMESPACE="$2"; shift 2 ;;
        --node-port)              NODE_PORT="$2"; shift 2 ;;
        --disable-node-port)      NODE_PORT_ENABLED="false"; shift ;;
        --ingress-class)          INGRESS_CLASS="$2"; shift 2 ;;
        --host)                   WEB_HOST="$2"; shift 2 ;;
        --web-scheme)             WEB_SCHEME="$2"; shift 2 ;;
        --disable-web)            WEB_ENABLED="false"; shift ;;
        --timeout)                WAIT_TIMEOUT="$2"; shift 2 ;;
        -h|--help)                usage ;;
        *) error "Unknown option: $1" ;;
    esac
done

case "$MODE" in
    ""|full|no-cluster-rbac|namespace-admin) ;;
    *) error "Unknown mode: $MODE (full, no-cluster-rbac or namespace-admin)" ;;
esac
case "$WEB_SCHEME" in
    http|https) ;;
    *) error "--web-scheme must be http or https" ;;
esac

check_prereqs() {
    info "Checking prerequisites..."
    local missing=()

    for cmd in helm openssl ssh-keygen kubectl curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools: ${missing[*]}"
    fi

    # Helm version >= 3
    local helm_major
    helm_major=$(helm version --short 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/' | head -1)
    if [ "${helm_major:-0}" -lt 3 ]; then
        error "Helm v3 or later is required (found: $(helm version --short 2>/dev/null))"
    fi

    # kubectl can reach a cluster (the version endpoint needs no permissions)
    if ! kubectl version -o json &>/dev/null; then
        error "kubectl cannot reach a Kubernetes cluster. Check your kubeconfig."
    fi

    info "All prerequisites met."
}

# can_i VERB RESOURCE [kubectl auth can-i options]: whether the current user
# may do it
can_i() {
    [ "$(kubectl auth can-i "$@" 2>/dev/null)" = "yes" ]
}

yesno() { if "$@"; then echo "yes"; else echo "no"; fi; }

# namespace_exists NS: the namespace exists (a namespace admin may read their
# own namespace's object; Forbidden counts as not found)
namespace_exists() {
    kubectl get namespace "$1" &>/dev/null
}

# installable_in NS: the user may create what the chart puts into a namespace
# (workloads, configuration, Roles). Checked for a namespace that doesn't exist
# yet too: then only cluster-wide grants count.
installable_in() {
    local ns="$1" r
    for r in deployments.apps statefulsets.apps services secrets configmaps \
             serviceaccounts persistentvolumeclaims roles.rbac.authorization.k8s.io \
             rolebindings.rbac.authorization.k8s.io networkpolicies.networking.k8s.io; do
        can_i create "$r" -n "$ns" || return 1
    done
}

# The rights beyond Kubernetes' built-in "admin" role that the provisioner
# needs for optional features; the user can grant them only when holding them.
quota_allowed()  { can_i create resourcequotas -n "$1" && can_i create limitranges -n "$1"; }
resize_allowed() { can_i patch pods --subresource=resize -n "$1"; }

api_group_present() {
    kubectl api-resources --api-group="$1" -o name 2>/dev/null | grep -q .
}

context_namespace() {
    local ns
    ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)
    echo "${ns:-default}"
}

current_user() {
    local who
    who=$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null || true)
    if [ -z "$who" ]; then
        who="context $(kubectl config current-context 2>/dev/null || echo '?')"
    fi
    echo "$who"
}

describe_file() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "$file (exists)"
    else
        echo "$file (will be generated)"
    fi
}

ensure_ec_key() {
    local file="$1"
    if [ ! -f "$file" ]; then
        info "Generating EC key: $file"
        openssl ecparam -name prime256v1 -genkey -noout -out "$file"
    fi
    cat "$file"
}

# a random password kept in a file, so upgrades keep it (the database and NATS
# are initialized with it)
ensure_password() {
    local file="$1"
    if [ ! -f "$file" ]; then
        info "Generating password: $file"
        (umask 077; openssl rand -hex 24 > "$file")
    fi
    cat "$file"
}

detect_admin_key_source() {
    for candidate in "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ecdsa.pub"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
    echo "(new Ed25519 key will be generated at $GENERATED_SSH_KEY)"
}

resolve_private_key_path() {
    for candidate in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ecdsa"; do
        if [ -f "${candidate}.pub" ]; then
            echo "$candidate"
            return
        fi
    done
    echo "$GENERATED_SSH_KEY"
}

generate_admin_public_key() {
    # generate public key from existing private key if available
    for candidate in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ecdsa"; do
        if [ -f "$candidate" ]; then
            ssh-keygen -y -f "$candidate"
            return
        fi
    done
    if [ -f "${GENERATED_SSH_KEY}.pub" ]; then
        info "Using previously generated SSH key: ${GENERATED_SSH_KEY}.pub"
        cat "${GENERATED_SSH_KEY}.pub"
        return
    fi
    info "Generating new Ed25519 SSH key pair: $GENERATED_SSH_KEY"
    ssh-keygen -t ed25519 -f "$GENERATED_SSH_KEY" -N "" -C "admin" >&2
    info "Private key saved to: $GENERATED_SSH_KEY"
    info "Public  key saved to: ${GENERATED_SSH_KEY}.pub"
    cat "${GENERATED_SSH_KEY}.pub"
}

# bcrypt_hash PASSWORD: the bcrypt hash identity expects for a local user's
# password, from the first tool available; empty when there is none.
bcrypt_hash() {
    local pw="$1"
    if command -v htpasswd &>/dev/null; then
        htpasswd -nbBC 10 "" "$pw" | tr -d ':\n'
    elif command -v python3 &>/dev/null && python3 -c 'import bcrypt' &>/dev/null; then
        PW="$pw" python3 -c 'import bcrypt,os; print(bcrypt.hashpw(os.environ["PW"].encode(), bcrypt.gensalt()).decode())'
    elif command -v mkpasswd &>/dev/null && mkpasswd -m help 2>/dev/null | grep -q bcrypt; then
        printf '%s' "$pw" | mkpasswd -m bcrypt --stdin
    fi
}

node_ip() {
    local ip
    ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)
    if [ -z "$ip" ]; then
        ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
    fi
    echo "${ip%% *}"
}

# The IngressClass for the web UI: the cluster's default class, else the only
# one. Listing IngressClasses needs a cluster-wide read; empty when unknown.
detect_ingress_class() {
    local classes default
    classes=$(kubectl get ingressclass -o name 2>/dev/null | sed 's|.*/||' || true)
    default=$(kubectl get ingressclass -o jsonpath='{range .items[?(@.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || true)
    if [ -n "$default" ]; then
        echo "$default"
    elif [ "$(echo "$classes" | grep -c .)" = "1" ]; then
        echo "$classes"
    fi
}

# ---------------------------------------------------------------------------
# Chart version: the newest CHART_SERIES.x in an OCI registry
# ---------------------------------------------------------------------------

# oci_token REGISTRY REPOSITORY: a pull token from the registry's token service
# (anonymous without credentials); empty when the registry needs none.
oci_token() {
    local registry="$1" repo="$2" challenge realm service auth=()
    challenge=$(curl -sI "https://$registry/v2/" | tr -d '\r' | grep -i '^www-authenticate: bearer' || true)
    [ -n "$challenge" ] || return 0
    realm=$(echo "$challenge" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')
    service=$(echo "$challenge" | sed -n 's/.*service="\([^"]*\)".*/\1/p')
    if [ -n "$REGISTRY_USERNAME" ] && [ "$registry" = "$REGISTRY_HOST" ]; then
        auth=(-u "$REGISTRY_USERNAME:$REGISTRY_PASSWORD")
    fi
    local resp tok
    resp=$(curl -s ${auth[@]+"${auth[@]}"} "$realm?service=$service&scope=repository:$repo:pull")
    tok=$(echo "$resp" | tr ',{}' '\n\n\n' | sed -n 's/^ *"token" *: *"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$tok" ] || tok=$(echo "$resp" | tr ',{}' '\n\n\n' | sed -n 's/^ *"access_token" *: *"\([^"]*\)".*/\1/p' | head -1)
    echo "$tok"
}

# newest_chart_version OCI_REF: the highest CHART_SERIES.x base version and,
# among its builds (pre-releases included), the one pushed last
newest_chart_version() {
    local ref="${1#oci://}" registry repo token tags base best="" best_time="" tag created
    registry="${ref%%/*}"
    repo="${ref#*/}"
    token=$(oci_token "$registry" "$repo")
    local hdr=()
    [ -n "$token" ] && hdr=(-H "Authorization: Bearer $token")
    tags=$(curl -s ${hdr[@]+"${hdr[@]}"} "https://$registry/v2/$repo/tags/list?n=10000" |
        tr ',[]' '\n\n\n' | sed -n 's/^ *"\([^"]*\)" *$/\1/p' | grep -E "^${CHART_SERIES}\.[0-9]+\.[0-9]+" || true)
    [ -n "$tags" ] || return 1
    base=$(echo "$tags" | sed 's/-.*//' | sort -uV | tail -1)
    for tag in $(echo "$tags" | grep -E "^${base//./\\.}(-|$)"); do
        created=$(curl -s ${hdr[@]+"${hdr[@]}"} -H "Accept: application/vnd.oci.image.manifest.v1+json" \
            "https://$registry/v2/$repo/manifests/$tag" |
            sed -n 's/.*"org.opencontainers.image.created" *: *"\([^"]*\)".*/\1/p')
        if [ -z "$best" ] || [[ "$created" > "$best_time" ]]; then
            best="$tag"
            best_time="$created"
        fi
    done
    echo "$best"
}

# image_archs IMAGE: the architectures an image is published for, one per
# line (from its index, or the config of a single-platform image); empty when
# the registry can't be read
image_archs() {
    local image="$1" registry repo tag token hdr=() manifest config
    registry="${image%%/*}"
    repo="${image#*/}"
    tag="${repo##*:}"
    repo="${repo%:*}"
    token=$(oci_token "$registry" "$repo")
    [ -n "$token" ] && hdr=(-H "Authorization: Bearer $token")
    manifest=$(curl -s ${hdr[@]+"${hdr[@]}"} \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
        "https://$registry/v2/$repo/manifests/$tag")
    if echo "$manifest" | grep -q '"manifests"'; then
        echo "$manifest" | tr ',{}' '\n\n\n' | sed -n 's/^ *"architecture" *: *"\([^"]*\)".*/\1/p' | grep -vx unknown | sort -u
    else
        config=$(echo "$manifest" | tr '\n' ' ' | sed -n 's/.*"config" *: *{[^}]*"digest" *: *"\([^"]*\)".*/\1/p')
        [ -n "$config" ] || return 0
        curl -sL ${hdr[@]+"${hdr[@]}"} "https://$registry/v2/$repo/blobs/$config" |
            tr ',{}' '\n\n\n' | sed -n 's/^ *"architecture" *: *"\([^"]*\)".*/\1/p' | head -1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

cat <<EOF
k8shell Quickstart v${SCRIPT_VERSION} — installs k8shell ${CHART_SERIES}.x with minimal setup.
For more information, see https://docs.k8shell.io/quickstart

EOF

check_prereqs

if [ -n "$REGISTRY_HOST" ] && { [ -z "$REGISTRY_USERNAME" ] || [ -z "$REGISTRY_PASSWORD" ]; }; then
    error "Credentials for $REGISTRY_HOST are required: --registry-username and --registry-password (or K8SHELL_REGISTRY_USERNAME and K8SHELL_REGISTRY_PASSWORD); --registry \"\" for public images"
fi

# --- What the user may do ----------------------------------------------------

info "Checking your permissions..."
USER_NAME=$(current_user)
CAN_CLUSTER_RBAC=$(yesno eval 'can_i create clusterroles && can_i create clusterrolebindings')
CAN_CREATE_NS=$(yesno can_i create namespaces)
CAN_LIST_NODES=$(yesno can_i list nodes)

# the proposed mode
if [ "$CAN_CLUSTER_RBAC" = "yes" ] && [ "$CAN_CREATE_NS" = "yes" ]; then
    PROPOSED="full"
    REASON="you may create cluster-scoped RBAC and namespaces"
elif [ "$CAN_CREATE_NS" = "yes" ]; then
    PROPOSED="no-cluster-rbac"
    REASON="you may create namespaces, but no cluster-scoped RBAC"
else
    PROPOSED="namespace-admin"
    REASON="you may create neither namespaces nor cluster-scoped RBAC"
fi
if [ -z "$MODE" ]; then
    MODE="$PROPOSED"
    MODE_NOTE="proposed: $REASON"
elif [ "$MODE" = "$PROPOSED" ]; then
    MODE_NOTE="chosen; also proposed: $REASON"
else
    MODE_NOTE="chosen; proposed was $PROPOSED: $REASON"
fi

# namespaces of the mode
if [ "$MODE" = "namespace-admin" ]; then
    NAMESPACE="${NAMESPACE:-$(context_namespace)}"
    TARGET_NAMESPACE="${TARGET_NAMESPACE:-$NAMESPACE}"
    WORKSPACE_NAMESPACE="${WORKSPACE_NAMESPACE:-$TARGET_NAMESPACE}"
else
    NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
    TARGET_NAMESPACE="${TARGET_NAMESPACE:-$DEFAULT_TARGET_NAMESPACE}"
    WORKSPACE_NAMESPACE="${WORKSPACE_NAMESPACE:-$TARGET_NAMESPACE-default}"
fi
if [ "$MODE" = "full" ]; then
    NAMESPACES=("$NAMESPACE" "$TARGET_NAMESPACE")
else
    NAMESPACES=("$NAMESPACE" "$TARGET_NAMESPACE" "$WORKSPACE_NAMESPACE")
fi
NAMESPACES=($(printf '%s\n' "${NAMESPACES[@]}" | awk '!seen[$0]++'))

# what the mode needs
PROBLEMS=()
if [ "$MODE" = "full" ] && [ "$CAN_CLUSTER_RBAC" != "yes" ]; then
    PROBLEMS+=("mode full needs cluster-scoped RBAC (ClusterRoles and ClusterRoleBindings)")
fi
NS_STATUS=()
for ns in "${NAMESPACES[@]}"; do
    if namespace_exists "$ns"; then
        status="exists"
    elif [ "$CAN_CREATE_NS" = "yes" ]; then
        status="will be created"
    else
        status="missing"
        PROBLEMS+=("namespace $ns does not exist and you may not create namespaces")
    fi
    if [ "$status" != "missing" ] && ! installable_in "$ns"; then
        PROBLEMS+=("you may not create workloads, configuration and Roles in namespace $ns")
    fi
    NS_STATUS+=("$ns ($status)")
done
if [ "$MODE" = "namespace-admin" ] && [ "$CAN_CREATE_NS" != "yes" ]; then
    : # nothing is created: the namespaces must exist (checked above)
fi

# optional features
if [ "$MODE" = "full" ]; then
    ORGANIZATIONS="on"
    QUOTA="on"
    LIVE_RESIZE="on"
    NODE_POOLS="on"
    if [ "$CAN_LIST_NODES" = "yes" ] && kubectl get --raw /apis/metrics.k8s.io/v1beta1 &>/dev/null; then
        NODE_USAGE="on"
    else
        NODE_USAGE="off (no metrics-server)"
    fi
else
    ORGANIZATIONS="off (single organization 'default')"
    NODE_POOLS="off"
    NODE_USAGE="off"
    if quota_allowed "$WORKSPACE_NAMESPACE"; then QUOTA="on"; else QUOTA="off (you may not grant quota rights)"; fi
    if resize_allowed "$WORKSPACE_NAMESPACE"; then LIVE_RESIZE="on"; else LIVE_RESIZE="off (you may not grant pods/resize)"; fi
    # Cilium: the provisioner's Role then includes CiliumNetworkPolicies
    if api_group_present cilium.io && ! can_i create ciliumnetworkpolicies.cilium.io -n "$WORKSPACE_NAMESPACE"; then
        PROBLEMS+=("the cluster runs Cilium, but you may not manage CiliumNetworkPolicies in $WORKSPACE_NAMESPACE: a cluster admin must aggregate them into the admin role first")
    fi
fi

# the SSH NodePort must be free (checked when services can be listed
# cluster-wide; a NodePort of this release itself is fine)
if [ "$NODE_PORT_ENABLED" = "true" ] && can_i list services --all-namespaces; then
    portUser=$(kubectl get services -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{" "}{.spec.ports[*].nodePort}{"\n"}{end}' 2>/dev/null |
        awk -v p="$NODE_PORT" '{for (i = 2; i <= NF; i++) if ($i == p) print $1}' | grep -v "^$NAMESPACE/" | head -1 || true)
    if [ -n "$portUser" ]; then
        PROBLEMS+=("NodePort $NODE_PORT is used by service $portUser: choose another with --node-port, or --disable-node-port")
    fi
fi

# web UI
if [ "$WEB_ENABLED" = "true" ]; then
    INGRESS_CLASS="${INGRESS_CLASS:-$(detect_ingress_class)}"
    if [ -z "$INGRESS_CLASS" ]; then
        WEB_ENABLED="false"
        WEB_NOTE="off: no IngressClass found (set --ingress-class); the web UI needs an ingress controller"
    else
        if [ -z "$WEB_HOST" ]; then
            ip=$(node_ip)
            [ -n "$ip" ] && WEB_HOST="$ip.nip.io"
        fi
        if [ -z "$WEB_HOST" ]; then
            WEB_ENABLED="false"
            WEB_NOTE="off: no host (set --host)"
        else
            WEB_NOTE="$WEB_SCHEME://$WEB_HOST (IngressClass $INGRESS_CLASS)"
        fi
    fi
else
    WEB_NOTE="off (--disable-web)"
fi

# chart version
if [ -z "$CHART_VERSION" ] && [[ "$CHART_REF" == oci://* ]]; then
    CHART_VERSION=$(newest_chart_version "$CHART_REF" || true)
    [ -n "$CHART_VERSION" ] || error "No ${CHART_SERIES}.x version of $CHART_REF found; set --version"
fi

# the chart is in the registry of the images: log in to read it
if [ -n "$REGISTRY_HOST" ] && [[ "$CHART_REF" == "oci://$REGISTRY_HOST/"* ]]; then
    printf '%s' "$REGISTRY_PASSWORD" | helm registry login "$REGISTRY_HOST" \
        --username "$REGISTRY_USERNAME" --password-stdin >/dev/null 2>&1 || true
fi

# a local chart directory needs its dependencies (the NATS subchart)
if [ -d "$CHART_REF" ] && helm dependency list "$CHART_REF" 2>/dev/null | awk 'NR > 1 && NF && $4 != "ok"' | grep -q .; then
    info "Building the dependencies of $CHART_REF..."
    helm dependency list "$CHART_REF" 2>/dev/null | awk 'NR > 1 && NF {print $1, $3}' | while read -r name repo; do
        case "$repo" in http*) helm repo add "$name" "$repo" >/dev/null 2>&1 || true ;; esac
    done
    helm dependency build "$CHART_REF" >/dev/null || error "helm dependency build $CHART_REF failed"
fi

# the chart sets the web UI's IngressClass only from 2.x builds that have
# the value ingress.className; older ones serve "k8shell-ingress" only
if [ "$WEB_ENABLED" = "true" ] && [ "$INGRESS_CLASS" != "k8shell-ingress" ]; then
    if ! helm show values "$CHART_REF" ${CHART_VERSION:+--version "$CHART_VERSION"} 2>/dev/null | grep -q '^ingress:'; then
        WEB_ENABLED="false"
        WEB_NOTE="off: chart ${CHART_VERSION:-$CHART_REF} serves the web UI only on the IngressClass k8shell-ingress (--ingress-class k8shell-ingress if the cluster has it)"
    fi
fi

# the web UI's address must reach the ingress controller (on a cluster in
# local VMs a LoadBalancer service gets no address: the controller has to
# listen on the nodes, e.g. hostPort 80/443)
WEB_WARNING=""
if [ "$WEB_ENABLED" = "true" ]; then
    code=$(curl -sk -o /dev/null --connect-timeout 3 --max-time 5 -w '%{http_code}' "$WEB_SCHEME://$WEB_HOST/" 2>/dev/null || true)
    if [ "${code:-000}" = "000" ]; then
        WEB_WARNING="nothing answers on $WEB_SCHEME://$WEB_HOST: the controller of the IngressClass $INGRESS_CLASS must be reachable there (a LoadBalancer address, or hostPort 80/443 on the nodes), or set --host to an address that reaches it"
    fi
fi

# a default StorageClass for the volumes of the database and NATS (checked
# when StorageClasses can be listed)
if can_i list storageclasses.storage.k8s.io; then
    defaultSC=$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || true)
    if [ -n "$defaultSC" ]; then
        STORAGE_NOTE="$defaultSC (the default StorageClass)"
    elif [ ${#VALUES_FILES[@]} -gt 0 ]; then
        STORAGE_NOTE="no default StorageClass: your values files must set the storage classes"
    else
        STORAGE_NOTE="no default StorageClass"
        PROBLEMS+=("the cluster has no default StorageClass for the volumes of the database and NATS: make one the default (on a local cluster, for example local-path: https://github.com/rancher/local-path-provisioner), or set the storage classes in a values file (-f)")
    fi
else
    STORAGE_NOTE="not checked (you may not list StorageClasses)"
fi

# the nodes' architectures must be in k8shell's images (checked when nodes
# can be read): the images the chart and the values files name, in the
# private registry or on ghcr.io
ARCH_NOTE="not checked (you may not read nodes)"
if [ "$CAN_LIST_NODES" = "yes" ]; then
    NODE_ARCHS=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.architecture}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ')
    vf=()
    for f in ${VALUES_FILES[@]+"${VALUES_FILES[@]}"}; do vf+=(-f "$f"); done
    images=$(helm template k8shell "$CHART_REF" ${CHART_VERSION:+--version "$CHART_VERSION"} --namespace "${NAMESPACE}" \
        --set provisioner.targetNamespace=check --set sshProxy.serverKey.value=check \
        --set postgresql.username.value=check --set postgresql.password.value=check --set nats.password.value=check \
        ${vf[@]+"${vf[@]}"} 2>/dev/null |
        grep -oE "(${REGISTRY_HOST:-registry.k8shell.io}|ghcr\.io/k8shell-io)/[a-z0-9._/-]+:[A-Za-z0-9._-]+" | sort -u || true)
    if [ -z "$images" ]; then
        ARCH_NOTE="nodes ${NODE_ARCHS% }; images not checked (the chart could not be rendered)"
    else
        archProblems=()
        for image in $images; do
            archs=$(image_archs "$image" | tr '\n' ' ')
            [ -n "$archs" ] || continue
            for a in $NODE_ARCHS; do
                if [[ " $archs " != *" $a "* ]]; then
                    archProblems+=("image $image is published for ${archs% } only, not for the nodes' $a")
                    break
                fi
            done
        done
        if [ ${#archProblems[@]} -eq 0 ]; then
            ARCH_NOTE="nodes ${NODE_ARCHS% }; k8shell's images support them"
        else
            ARCH_NOTE="nodes ${NODE_ARCHS% }; ${#archProblems[@]} image(s) don't support them (see below)"
            PROBLEMS+=("${archProblems[@]}")
            PROBLEMS+=("use a chart version or images (-f) built for ${NODE_ARCHS% }")
        fi
    fi
fi

mkdir -p "$QUICKSTART_DIR"

serverKeyDesc=$(describe_file "$QUICKSTART_DIR/server-key.pem" | sed "s|$HOME|~|g")
jwtKeyDesc=$(describe_file "$QUICKSTART_DIR/jwt-key.pem" | sed "s|$HOME|~|g")
adminKeySource=$(detect_admin_key_source | sed "s|$HOME|~|g")
adminPasswordDesc=$(describe_file "$QUICKSTART_DIR/admin-password" | sed "s|$HOME|~|g")

if helm status k8shell --namespace "$NAMESPACE" &>/dev/null; then
    helmAction="upgrade"
else
    helmAction="install"
fi

echo
echo "  Kubernetes user    : $USER_NAME"
echo "  Permissions        : cluster RBAC $CAN_CLUSTER_RBAC, create namespaces $CAN_CREATE_NS, read nodes $CAN_LIST_NODES"
echo "  Mode               : $MODE ($MODE_NOTE)"
echo "  Organizations      : $ORGANIZATIONS"
echo "  Node pools         : $NODE_POOLS"
echo "  Node usage         : $NODE_USAGE"
echo "  Organization quota : $QUOTA"
echo "  Live resize        : $LIVE_RESIZE"
echo "  Helm action        : $helmAction"
echo "  Chart              : $CHART_REF ${CHART_VERSION:-(local)}"
for f in ${VALUES_FILES[@]+"${VALUES_FILES[@]}"}; do
echo "  Values file        : $f"
done
echo "  Images             : ${REGISTRY_HOST:-public registry}${REGISTRY_HOST:+ (with credentials)}"
echo "  Architectures      : $ARCH_NOTE"
echo "  Storage            : $STORAGE_NOTE"
echo "  Release namespace  : $NAMESPACE"
echo "  Target namespace   : $TARGET_NAMESPACE"
[ "$MODE" != "full" ] && \
echo "  Workspace namespace: $WORKSPACE_NAMESPACE"
echo "  Namespaces         : ${NS_STATUS[*]}"
echo "  Web UI             : $WEB_NOTE"
echo "  SSH NodePort       : $([ "$NODE_PORT_ENABLED" = "true" ] && echo "enabled (port $NODE_PORT)" || echo "disabled")"
echo "  SSH proxy key      : $serverKeyDesc"
echo "  JWT signing key    : $jwtKeyDesc"
echo "  Admin user         : admin (sudo enabled, shell: /bin/bash)"
echo "  Admin SSH key      : $adminKeySource"
echo "  Admin web password : $adminPasswordDesc"
echo

[ -n "$WEB_WARNING" ] && warn "web UI: $WEB_WARNING"

if [ ${#PROBLEMS[@]} -gt 0 ]; then
    for p in "${PROBLEMS[@]}"; do
        warn "$p"
    done
    error "k8shell can't be installed in mode $MODE because of the problems above (see the [WRN] lines)"
fi

# --- Values ------------------------------------------------------------------

yamlQuote() { printf "'%s'" "${1//\'/\'\'}"; }
modeValues="$QUICKSTART_DIR/mode-values.yaml"
{
    echo "# generated by quickstart-v2.sh: mode $MODE"
    if [ "$MODE" = "full" ]; then
        cat <<EOV
provisioner:
  nodeUsage:
    enabled: $([ "$NODE_USAGE" = "on" ] && echo true || echo false)
    nodeMetrics: true
    otherPods: true
EOV
    else
        cat <<EOV
organizations:
  enabled: false
  defaultNamespace:
    name: $(yamlQuote "$WORKSPACE_NAMESPACE")
    create: false
    quota: $([ "$QUOTA" = "on" ] && echo true || echo false)
provisioner:
  liveResize: $([ "$LIVE_RESIZE" = "on" ] && echo true || echo false)
  nodeSelectorKeys: []
  nodeUsage:
    enabled: false
EOV
    fi
    if [ "$WEB_ENABLED" = "true" ]; then
        cat <<EOV
ingress:
  className: $(yamlQuote "$INGRESS_CLASS")
frontend:
  host: $(yamlQuote "$WEB_HOST")
  scheme: $WEB_SCHEME
EOV
    fi
} > "$modeValues"

if [ "$DRY_RUN" = "true" ]; then
    info "Dry run: the mode's values ($modeValues):"
    cat "$modeValues" >&2
    info "Dry run: nothing installed."
    exit 0
fi

if [ "$ASSUME_YES" = "true" ]; then
    confirm="y"
else
    read -rp "Proceed with installation? [y/N] " confirm </dev/tty
fi
case "$confirm" in
    [yY][eE][sS]|[yY]) ;;
    *) info "Installation cancelled."; exit 0 ;;
esac

# the namespaces (helm creates none: in namespace-admin mode they exist, and
# the release namespace may be one the user can't create)
for ns in "${NAMESPACES[@]}"; do
    if ! namespace_exists "$ns"; then
        info "Creating namespace: $ns"
        kubectl create namespace "$ns"
    fi
done

serverKey=$(ensure_ec_key "$QUICKSTART_DIR/server-key.pem")
# the JWT signing key is kept too: the chart would generate a new one on every
# upgrade, and services that don't restart would reject the new tokens
jwtKey=$(ensure_ec_key "$QUICKSTART_DIR/jwt-key.pem")
dbPassword=$(ensure_password "$QUICKSTART_DIR/db-password")
natsPassword=$(ensure_password "$QUICKSTART_DIR/nats-password")
adminKey=$(generate_admin_public_key)
adminPassword=$(ensure_password "$QUICKSTART_DIR/admin-password")
adminPasswordHash=$(bcrypt_hash "$adminPassword")
if [ -z "$adminPasswordHash" ]; then
    warn "No bcrypt tool found (htpasswd, python3 with bcrypt, or mkpasswd): the web UI password of 'admin' is not set; install one and run this script again"
fi
privateKeyPath=$(resolve_private_key_path | sed "s|$HOME|~|g")

nodeIp=""
if [ "$NODE_PORT_ENABLED" = "true" ]; then
    nodeIp=$(node_ip)
fi

valuesArgs=(-f "$modeValues")

if [ -n "$REGISTRY_HOST" ]; then
    # Registry credentials as a values file (not --set: passwords may hold
    # commas); services pull with the pull Secret, workspaces pull k8shelld
    # through the provisioner's private registry.
    registryValues="$QUICKSTART_DIR/registry-values.yaml"
    (umask 077; cat > "$registryValues" <<EOV
imageRegistry:
  host: $(yamlQuote "$REGISTRY_HOST")
  username: $(yamlQuote "$REGISTRY_USERNAME")
  password: $(yamlQuote "$REGISTRY_PASSWORD")
provisioner:
  privateRegistry:
    enabled: true
    host: {value: $(yamlQuote "$REGISTRY_HOST")}
    username: {value: $(yamlQuote "$REGISTRY_USERNAME")}
    password: {value: $(yamlQuote "$REGISTRY_PASSWORD")}
EOV
    )
    valuesArgs+=(-f "$registryValues")

    # the chart itself is in the same registry
    if [[ "$CHART_REF" == "oci://$REGISTRY_HOST/"* ]]; then
        printf '%s' "$REGISTRY_PASSWORD" | helm registry login "$REGISTRY_HOST" \
            --username "$REGISTRY_USERNAME" --password-stdin >/dev/null \
            || error "helm registry login to $REGISTRY_HOST failed"
    fi
fi
for f in ${VALUES_FILES[@]+"${VALUES_FILES[@]}"}; do
    valuesArgs+=(-f "$f")
done

info "Running helm $helmAction for k8shell ${CHART_VERSION:-(local chart)}; waiting up to $WAIT_TIMEOUT for it to start..."

# On failure (typically a component that doesn't become ready in time) show
# what isn't ready, before set -e ends the script.
helm_failed() {
    warn "helm $helmAction failed; pods in $NAMESPACE that are not ready:"
    kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null |
        awk '{split($2, r, "/"); if (r[1] != r[2] || $3 != "Running") print "  " $0}' >&2 || true
    warn "see their logs (kubectl logs -n $NAMESPACE <pod>), fix the cause and run this script again"
}
trap 'helm_failed' ERR

helm upgrade --install k8shell "$CHART_REF" \
  ${CHART_VERSION:+--version "$CHART_VERSION"} \
  --namespace "$NAMESPACE" \
  --wait --timeout "$WAIT_TIMEOUT" \
  --set provisioner.targetNamespace="$TARGET_NAMESPACE" \
  --set sshProxy.serverKey.value="$serverKey" \
  --set identity.jwtIssuer.privateKey.value="$jwtKey" \
  --set identity.jwtIssuer.signingMethod.value=es256 \
  --set postgresql.username.value=k8shell \
  --set postgresql.password.value="$dbPassword" \
  --set nats.password.value="$natsPassword" \
  --set identity.users[0].username=admin \
  --set identity.users[0].uid=1001 \
  --set identity.users[0].gid=1001 \
  --set identity.users[0].publicKey="$adminKey" \
  --set identity.users[0].sudo="true" \
  --set identity.users[0].roles[0]=admin \
  --set identity.users[0].roles[1]=developer \
  --set identity.users[0].organization=default \
  --set identity.users[0].shell="/bin/bash" \
  ${adminPasswordHash:+--set-string identity.users[0].password="$adminPasswordHash"} \
  ${adminPasswordHash:+--set apiServer.localProvider.enabled=true} \
  --set sshProxy.nodePort.enabled="$NODE_PORT_ENABLED" \
  --set sshProxy.nodePort.port="$NODE_PORT" \
  ${valuesArgs[@]+"${valuesArgs[@]}"}

trap - ERR
info "k8shell $([ "$helmAction" = "install" ] && echo installed || echo upgraded) successfully (mode $MODE)."

cat <<EOF

  Next steps
  ----------
  1. Connect to the workspace 'ubuntu' as 'admin' user:
$(if [ "$NODE_PORT_ENABLED" = "true" ]; then
echo ""
echo "       ssh -p $NODE_PORT -i ${privateKeyPath} admin~ubuntu@${nodeIp:-<node-ip>}"
else
echo ""
echo "     Start port-forwarding:"
echo ""
echo "       kubectl port-forward svc/ssh-internal 2222:22 -n ${NAMESPACE}"
echo ""
echo "     Connect:"
echo ""
echo "       ssh -p 2222 -i ${privateKeyPath} admin~ubuntu@127.0.0.1"
fi)

  2. Web UI:
$(if [ "$WEB_ENABLED" = "true" ]; then
echo ""
echo "       $WEB_SCHEME://$WEB_HOST"
echo ""
echo "     served by the IngressClass '$INGRESS_CLASS' (accept its certificate if"
echo "     it is self-signed). Sign in as 'admin' with the password in"
echo "     $(echo "$QUICKSTART_DIR/admin-password" | sed "s|$HOME|~|g")."
else
echo ""
echo "     not set up ($WEB_NOTE)."
fi)

EOF
