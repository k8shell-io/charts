#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# k8shell quickstart
# ---------------------------------------------------------------------------

CHART_VERSION="1.2.5-pr-27-a53f90f"
NAMESPACE="k8shell-system"
TARGET_NAMESPACE="k8shell-workspaces"
GENERATED_SSH_KEY="./admin-ssh-key"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -v, --version VERSION     Helm chart version         (default: $CHART_VERSION)
  -n, --namespace NS        k8shell release namespace  (default: $NAMESPACE)
  -t, --target-namespace NS Workspace target namespace (default: $TARGET_NAMESPACE)
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

serverKeyDesc=$(describe_ec_key ./server-key.pem)
issuerKeyDesc=$(describe_ec_key ./issuer-key.pem)
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
echo "  Chart version      : $CHART_VERSION"
echo "  Release namespace  : $NAMESPACE (will be created if absent)"
echo "  Target namespace   : $TARGET_NAMESPACE ($targetNsStatus)"
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

serverKey=$(ensure_ec_key ./server-key.pem)
issuerKey=$(ensure_ec_key ./issuer-key.pem)
adminKey=$(generate_admin_public_key)
privateKeyPath=$(resolve_private_key_path)

info "Running helm $helmAction for k8shell v${CHART_VERSION}..."

helm $helmAction k8shell oci://registry.k8shell.io/charts/k8shell \
  --version "$CHART_VERSION" \
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
  --set identity.users[0].shell="/bin/bash"

info "k8shell ${helmAction}ed successfully."

cat <<EOF

  Next steps
  ----------
  1. Start port-forwarding to the SSH proxy:

       kubectl port-forward svc/ssh-internal 2222:22 -n ${NAMESPACE}

  2. Connect to the workspace 'ubuntu' as 'admin' user:

       ssh -p 2222 -i ${privateKeyPath} admin~ubuntu@127.0.0.1

EOF