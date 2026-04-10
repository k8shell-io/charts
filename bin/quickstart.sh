#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# k8shell quickstart
# ---------------------------------------------------------------------------

CHART_VERSION=""
NAMESPACE="k8shell-system"
TARGET_NAMESPACE="k8shell-workspaces"
QUICKSTART_DIR="$HOME/k8shell-quickstart"
GENERATED_SSH_KEY="$QUICKSTART_DIR/admin-ssh-key"
NODE_PORT_ENABLED="true"
NODE_PORT="30022"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -v, --version VERSION     Helm chart version         (default: latest)
  -n, --namespace NS        k8shell release namespace  (default: $NAMESPACE)
  -t, --target-namespace NS Workspace target namespace (default: $TARGET_NAMESPACE)
      --node-port PORT      Expose SSH via NodePort     (default: $NODE_PORT)
      --disable-node-port    Disable NodePort SSH service
  -h, --help                Show this help message
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)           CHART_VERSION="$2"; shift 2 ;;
        -n|--namespace)         NAMESPACE="$2";       shift 2 ;;
        -t|--target-namespace)  TARGET_NAMESPACE="$2"; shift 2 ;;
        --node-port)            NODE_PORT="$2"; shift 2 ;;
        --disable-node-port)     NODE_PORT_ENABLED="false"; shift ;;
        -h|--help)              usage ;;
        *) error "Unknown option: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "[INF] $*" >&2; }
warn()  { echo "[WRN] $*" >&2; }
error() { echo "[ERR] $*" >&2; exit 1; }

check_prereqs() {
    info "Checking prerequisites..."
    local missing=()

    for cmd in helm openssl ssh-keygen kubectl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools: ${missing[*]}"
    fi

    # Helm version >= 3
    local helm_major
    helm_major=$(helm version --short 2>/dev/null | grep -oP 'v\K[0-9]+' | head -1)
    if [ "${helm_major:-0}" -lt 3 ]; then
        error "Helm v3 or later is required (found: $(helm version --short 2>/dev/null))"
    fi

    # kubectl can reach a cluster
    if ! kubectl cluster-info &>/dev/null; then
        error "kubectl cannot reach a Kubernetes cluster. Check your kubeconfig."
    fi

    info "All prerequisites met."
}

describe_ec_key() {
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

resolve_admin_public_key() {
    # 1. Prefer ~/.ssh/id_rsa.pub if it exists
    local default_pub="$HOME/.ssh/id_rsa.pub"
    if [ -f "$default_pub" ]; then
        info "Using existing SSH public key: $default_pub"
        cat "$default_pub"
        return
    fi

    # 2. Also check common Ed25519 / ECDSA defaults
    for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ecdsa.pub"; do
        if [ -f "$candidate" ]; then
            info "Using existing SSH public key: $candidate"
            cat "$candidate"
            return
        fi
    done

    # 3. Key will be generated after user approval — not yet
    return 1
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
    # Returns existing key content, or generates a new pair and returns the public key
    for candidate in "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ecdsa.pub"; do
        if [ -f "$candidate" ]; then
            cat "$candidate"
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

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

cat <<EOF
k8shell Quickstart — installs k8shell with minimal setup.
For more information, see https://docs.k8shell.io/quickstart

EOF

check_prereqs

mkdir -p "$QUICKSTART_DIR"

serverKeyDesc=$(describe_ec_key "$QUICKSTART_DIR/server-key.pem")
issuerKeyDesc=$(describe_ec_key "$QUICKSTART_DIR/issuer-key.pem")
adminKeySource=$(detect_admin_key_source)

if kubectl get namespace "$TARGET_NAMESPACE" &>/dev/null; then
    targetNsStatus="exists"
else
    targetNsStatus="will be created"
fi

if helm status k8shell --namespace "$NAMESPACE" &>/dev/null; then
    helmAction="upgrade"
else
    helmAction="install"
fi

echo 
echo "  Helm action        : $helmAction"
echo "  Chart version      : ${CHART_VERSION:-latest}"
echo "  Release namespace  : $NAMESPACE (will be created if absent)"
echo "  Target namespace   : $TARGET_NAMESPACE ($targetNsStatus)"
echo "  SSH NodePort       : $([ "$NODE_PORT_ENABLED" = "true" ] && echo "enabled (port $NODE_PORT)" || echo "disabled")"
echo "  SSH proxy key      : $serverKeyDesc"
echo "  JWT issuer key     : $issuerKeyDesc"
echo "  Admin user         : admin (sudo enabled, shell: /bin/bash)"
echo "  Admin SSH key      : $adminKeySource"
echo
read -rp "Proceed with installation? [y/N] " confirm
case "$confirm" in
    [yY][eE][sS]|[yY]) ;;
    *) info "Installation cancelled."; exit 0 ;;
esac

if [ "$targetNsStatus" = "will be created" ]; then
    info "Creating target namespace: $TARGET_NAMESPACE"
    kubectl create namespace "$TARGET_NAMESPACE"
fi

serverKey=$(ensure_ec_key "$QUICKSTART_DIR/server-key.pem")
issuerKey=$(ensure_ec_key "$QUICKSTART_DIR/issuer-key.pem")
adminKey=$(generate_admin_public_key)
privateKeyPath=$(resolve_private_key_path)

nodeIp=""
if [ "$NODE_PORT_ENABLED" = "true" ]; then
    nodeIp=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)
    if [ -z "$nodeIp" ]; then
        nodeIp=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
    fi
fi

info "Running helm $helmAction for k8shell ${CHART_VERSION:-latest}..."

helm $helmAction k8shell oci://registry.k8shell.io/charts/k8shell \
  ${CHART_VERSION:+--version "$CHART_VERSION"} \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set provisioner.targetNamespace="$TARGET_NAMESPACE" \
  --set sshProxy.serverKey.value="$serverKey" \
  --set identity.jwtIssuer.privateKey.value="$issuerKey" \
  --set identity.jwtIssuer.signingMethod.value="es256" \
  --set identity.users[0].username=admin \
  --set identity.users[0].uid=1001 \
  --set identity.users[0].gid=1001 \
  --set identity.users[0].publicKey="$adminKey" \
  --set identity.users[0].sudo="true" \
  --set identity.users[0].shell="/bin/bash" \
  --set sshProxy.nodePort.enabled="$NODE_PORT_ENABLED" \
  --set sshProxy.nodePort.port="$NODE_PORT"

info "k8shell ${helmAction}ed successfully."

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

EOF