#!/usr/bin/env bash
# Checks which cluster-scoped objects the chart renders for each combination
# of the features that need them (organizations, node features, cluster-wide
# injection): exactly the expected ones, and none at all for a minimal
# installation (organizations off with an existing namespace, no node
# features, no injection into every namespace).
# Needs helm and the chart's dependencies (helm dependency build k8shell).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
chart="$(dirname "$here")"

# the settings every render needs (secrets the chart insists on)
base=(
  --namespace k8shell-system
  --set provisioner.targetNamespace=k8shell-workspaces
  --set sshProxy.serverKey.value=test
  --set postgresql.username.value=test --set postgresql.password.value=test
  --set nats.password.value=test
)
minimal=(
  --set organizations.enabled=false --set organizations.defaultNamespace.create=false
  --set provisioner.nodeSelectorKeys=null --set provisioner.nodeUsage.enabled=false
)

# Kinds that are not namespaced. A new one rendered by the chart must be
# added here, or this test can't see it.
cluster_kinds='Namespace|ClusterRole|ClusterRoleBinding|CustomResourceDefinition|PriorityClass|StorageClass|IngressClass|RuntimeClass|PersistentVolume|ValidatingWebhookConfiguration|MutatingWebhookConfiguration|ValidatingAdmissionPolicy|ValidatingAdmissionPolicyBinding|APIService|ClusterIssuer'

failed=0

# cluster_objects <helm args...>: "Kind/name" of every cluster-scoped object, sorted
cluster_objects() {
  helm template k8shell "$chart" "${base[@]}" "$@" |
    awk -v kinds="^(${cluster_kinds})$" '
      /^---/ { kind = ""; inmeta = 0; next }
      /^kind: / { kind = $2; next }
      /^metadata:/ { inmeta = 1; next }
      inmeta && /^  name: / { if (kind ~ kinds) print kind "/" $2; inmeta = 0 }
      /^[^ ]/ && !/^metadata:/ { inmeta = 0 }
    ' | sort
}

# check <name> <expected, one per line or empty> <helm args...>
check() {
  local name="$1" want="$2"
  shift 2
  local got
  if ! got="$(cluster_objects "$@" 2>&1)"; then
    echo "FAIL $name: render failed: $got"
    failed=1
    return
  fi
  want="$(printf '%s' "$want" | sed '/^$/d' | sort)"
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/     /' || true
    failed=1
  fi
}

# check_fails <name> <message part> <helm args...>: the render must be refused
check_fails() {
  local name="$1" msg="$2"
  shift 2
  local out
  if out="$(helm template k8shell "$chart" "${base[@]}" "$@" 2>&1)"; then
    echo "FAIL $name: rendered, want an error containing \"$msg\""
    failed=1
  elif [[ "$out" != *"$msg"* ]]; then
    echo "FAIL $name: $out"
    failed=1
  else
    echo "ok   $name"
  fi
}

org_rbac='ClusterRole/provisioner-org-namespaces-k8shell-system
ClusterRole/provisioner-workspaces-k8shell-system
ClusterRoleBinding/provisioner-org-namespaces-k8shell-system'
node_rbac='ClusterRole/provisioner-nodes-k8shell-system
ClusterRoleBinding/provisioner-nodes-k8shell-system'
inject_rbac='ClusterRole/identity-inject-k8shell-system
ClusterRole/provisioner-inject-k8shell-system
ClusterRoleBinding/identity-inject-k8shell-system
ClusterRoleBinding/provisioner-inject-k8shell-system'

check "defaults: organizations and node selector discovery" "$org_rbac
$node_rbac"
check "minimal installation: no cluster-scoped object" "" "${minimal[@]}"
check "minimal, the chart creates the default namespace: only it" \
  "Namespace/k8shell-workspaces-default" \
  "${minimal[@]}" --set organizations.defaultNamespace.create=true
check "minimal, the target namespace as the default namespace" "" \
  "${minimal[@]}" --set organizations.defaultNamespace.name=k8shell-workspaces \
  --set organizations.defaultNamespace.create=true
check "minimal with explicit inject namespaces: Roles only" "" \
  "${minimal[@]}" --set 'provisioner.injectNamespaces={team-a,team-b}'
check "minimal with cluster-wide injection" "$inject_rbac" \
  "${minimal[@]}" --set 'provisioner.injectNamespaces={*}'
check "minimal with node usage" "$node_rbac" \
  "${minimal[@]}" --set provisioner.nodeUsage.enabled=true
check "minimal with node selector discovery" "$node_rbac" \
  "${minimal[@]}" --set 'provisioner.nodeSelectorKeys={k8shell.io/pool,kubernetes.io/os}'
check "organizations on, no node features" "$org_rbac" \
  --set provisioner.nodeSelectorKeys=null
check_fails "organizations off needs exactly one organization" "exactly one organization" \
  --set organizations.enabled=false \
  --set 'identity.organizations[0].name=default' --set 'identity.organizations[1].name=acme'

# check_rules_absent <name> <rule pattern> <helm args...>: no Role or
# ClusterRole grants a resource matching the pattern
check_rules_absent() {
  local name="$1" pattern="$2"
  shift 2
  if helm template k8shell "$chart" "${base[@]}" "$@" | grep -Eq "$pattern"; then
    echo "FAIL $name: rendered a rule matching $pattern"
    failed=1
  else
    echo "ok   $name"
  fi
}

# Installed by a namespace admin: nothing beyond Kubernetes' built-in
# "admin" role (no quota rights, no in-place resize).
nsadmin=("${minimal[@]}" --set organizations.defaultNamespace.quota=false --set provisioner.liveResize=false)
check "namespace admin installation: no cluster-scoped object" "" "${nsadmin[@]}"
check_rules_absent "namespace admin installation: no quota rights" '"(resourcequotas|limitranges)"' "${nsadmin[@]}"
check_rules_absent "namespace admin installation: no pods/resize" '"pods/resize"' "${nsadmin[@]}"
check_fails "no quota for the single organization when quotas are off" "can't have a quota" \
  "${nsadmin[@]}" --set 'identity.organizations[0].name=default' --set 'identity.organizations[0].quota.workspaces=5'

exit "$failed"
