package threat_test

import rego.v1

# --- fixtures ---

users := {
    "alice": {"username": "alice", "organization": "acme", "roles": ["dev-user"]},
    "bob": {"username": "bob", "organization": "acme", "roles": ["dev-admin"]},
    "carol": {"username": "carol", "organization": "other", "roles": ["dev-user"]},
    "gina": {"username": "gina", "organization": "acme", "roles": ["ops-user"]},
    "orga": {"username": "orga", "organization": "acme", "roles": ["org-admin"]},
    "root": {"username": "root", "organization": "acme", "roles": ["admin"]},
    "dave": {"username": "dave", "organization": "acme", "roles": ["dev-user", "detect-all"]},
    "erin": {"username": "erin", "organization": "acme", "roles": ["dev-user", "detect-exfil", "detect-crypto"]},
    "sam": {"username": "sam", "organization": "acme", "roles": ["dev-user"], "sudo": true},
}

subject(name) := {
    "username": name,
    "org": users[name].organization,
    "roles": users[name].roles,
}

mock_enrich_user(name) := users[name]

detect_input(who) := {
    "action": "threat:detect",
    "subject": subject(who),
    "resource": {"type": "workspace", "id": "ws1", "attributes": {"owner": who, "blueprint": "default"}},
    "context": {"mode": "standalone", "namespace": "workspaces"},
}

inject_input(who) := json.patch(detect_input(who), [{"op": "replace", "path": "/context", "value": {
    "mode": "inject", "namespace": "app", "workload_name": "web", "workload_kind": "Deployment",
}}])

override_input(who, owner) := {
    "action": "threat:detection:override",
    "subject": subject(who),
    "resource": {"type": "workspace", "id": "ws1", "attributes": {"owner": owner}},
    "context": {},
}

override_probe(who, owner) := json.remove(override_input(who, owner), ["resource/id"])

# a decision is allowed when allow holds and no deny fires, as the authz
# service evaluates it
threat_allowed(inp) if {
    data.threat.allow with input as inp with enrich.user as mock_enrich_user
    not data.threat.deny with input as inp with enrich.user as mock_enrich_user
}

detect_obligation(inp) := ob if {
    ob := data.threat.obligations.detect with input as inp with enrich.user as mock_enrich_user
}

# --- detect obligation ---

test_detect_none_by_default if {
    every who in {"alice", "bob", "orga", "root"} {
        detect_obligation(detect_input(who)) == "none"
        detect_obligation(inject_input(who)) == "none"
    }
}

test_detect_all_with_detect_all_role if detect_obligation(detect_input("dave")) == "all"

test_detect_categories_from_roles if detect_obligation(detect_input("erin")) == "crypto,exfil"

test_detect_rule_by_org_and_blueprint if {
    rules := [{"org": "acme", "blueprint": "default", "categories": {"exfil"}}]
    data.threat.obligations.detect == "exfil" with input as detect_input("alice") with data.threat.detect_rules as rules with enrich.user as mock_enrich_user
    data.threat.obligations.detect == "none" with input as detect_input("carol") with data.threat.detect_rules as rules with enrich.user as mock_enrich_user
}

test_detect_rule_all_wins if {
    rules := [{"org": "acme", "blueprint": "default", "categories": {"all"}}]
    data.threat.obligations.detect == "all" with input as detect_input("erin") with data.threat.detect_rules as rules with enrich.user as mock_enrich_user
}

# --- detect from rendered workspace resources ---

plain_pod := {
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {"name": "alice-85a782e", "namespace": "workspaces"},
    "spec": {
        "containers": [{"name": "workspace", "image": "ws:latest", "securityContext": {"runAsUser": 1000}}],
        "initContainers": [{"name": "init", "image": "k8shelld:latest"}],
        "volumes": [{"name": "home", "persistentVolumeClaim": {"claimName": "alice-home"}}],
    },
}

plain_netpol := {
    "apiVersion": "networking.k8s.io/v1",
    "kind": "NetworkPolicy",
    "metadata": {"name": "alice-85a782e"},
    "spec": {"podSelector": {}, "egress": [{"to": [{"ipBlock": {"cidr": "10.0.0.0/8"}}]}]},
}

plain_configmap := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "alice-85a782e-init"}}

# the rendered chart of a plain workspace, keyed "Kind/name"
plain_resources := {
    "Pod/alice-85a782e": plain_pod,
    "NetworkPolicy/alice-85a782e": plain_netpol,
    "ConfigMap/alice-85a782e-init": plain_configmap,
}

# detect_input(who) with resources as context.resources
resources_input(who, resources) := json.patch(detect_input(who), [{
    "op": "add", "path": "/context/resources", "value": json.marshal(resources),
}])

# detect_input(who) rendering plain_resources with the pod patched with ops
pod_input(who, ops) := resources_input(who, json.patch(plain_resources, [
    {"op": "replace", "path": "/Pod~1alice-85a782e", "value": json.patch(plain_pod, ops)},
]))

classes(inp) := cls if {
    cls := data.threat.detection_classes with input as inp with enrich.user as mock_enrich_user
}

test_detect_plain_pod_has_no_class if {
    classes(pod_input("alice", [])) == set()
    detect_obligation(pod_input("alice", [])) == "none"
}

test_detect_resources_absent_has_no_class if {
    classes(detect_input("alice")) == set()
    detect_obligation(detect_input("alice")) == "none"
    detect_obligation(detect_input("dave")) == "all"
}

test_detect_privileged_container if {
    inp := pod_input("alice", [{"op": "add", "path": "/spec/containers/0/securityContext/privileged", "value": true}])
    classes(inp) == {"privileged"}
    detect_obligation(inp) == "container-escape,privilege-escalation-and-kernel"
}

test_detect_privileged_init_container if {
    inp := pod_input("alice", [{"op": "add", "path": "/spec/initContainers/0/securityContext", "value": {"privileged": true}}])
    classes(inp) == {"privileged"}
}

test_detect_privileged_false_is_no_class if {
    inp := pod_input("alice", [{"op": "add", "path": "/spec/containers/0/securityContext/privileged", "value": false}])
    classes(inp) == set()
}

test_detect_kernel_capability if {
    inp := pod_input("alice", [{"op": "add", "path": "/spec/containers/0/securityContext/capabilities", "value": {"add": ["NET_BIND_SERVICE", "SYS_ADMIN"]}}])
    classes(inp) == {"privileged"}
    benign := pod_input("alice", [{"op": "add", "path": "/spec/containers/0/securityContext/capabilities", "value": {"add": ["NET_BIND_SERVICE"]}}])
    classes(benign) == set()
}

test_detect_host_namespaces if {
    every field in {"hostPID", "hostIPC"} {
        inp := pod_input("alice", [{"op": "add", "path": concat("", ["/spec/", field]), "value": true}])
        classes(inp) == {"host-namespaces"}
        detect_obligation(inp) == "container-escape,privilege-escalation-and-kernel"
    }
}

test_detect_host_network if {
    inp := pod_input("alice", [{"op": "add", "path": "/spec/hostNetwork", "value": true}])
    classes(inp) == {"host-network"}
}

test_detect_host_path if {
    inp := pod_input("alice", [{"op": "add", "path": "/spec/volumes/-", "value": {"name": "sock", "hostPath": {"path": "/var/run"}}}])
    classes(inp) == {"host-path"}
}

test_detect_root_pod_is_no_class if {
    # k8shelld always runs as root, so runAsUser 0 alone classifies nothing
    inp := pod_input("alice", [{"op": "replace", "path": "/spec/containers/0/securityContext/runAsUser", "value": 0}])
    classes(inp) == set()
}

test_detect_sudo_owner if {
    classes(pod_input("sam", [])) == {"sudo"}
    detect_obligation(pod_input("sam", [])) == "privilege-escalation-and-kernel"
    # without resources too: sudo comes from the owner's account
    detect_obligation(detect_input("sam")) == "privilege-escalation-and-kernel"
}

test_detect_sudo_is_the_owners_not_the_subjects if {
    # root provisions for sam: sam's sudo counts
    for_sam := json.patch(pod_input("root", []), [{"op": "replace", "path": "/resource/attributes/owner", "value": "sam"}])
    classes(for_sam) == {"sudo"}
    # sam provisions for alice: sam's sudo does not
    for_alice := json.patch(pod_input("sam", []), [{"op": "replace", "path": "/resource/attributes/owner", "value": "alice"}])
    classes(for_alice) == set()
}

test_detect_cluster_access if {
    binding := {"kind": "RoleBinding", "metadata": {"name": "alice"}, "roleRef": {"kind": "Role", "name": "edit"}}
    inp := resources_input("alice", object.union(plain_resources, {"RoleBinding/alice": binding}))
    classes(inp) == {"cluster-access"}
}

test_detect_open_egress if {
    netpol := json.patch(plain_netpol, [{"op": "add", "path": "/spec/egress/-", "value": {"to": [{"ipBlock": {"cidr": "0.0.0.0/0"}}]}}])
    inp := resources_input("alice", object.union(plain_resources, {"NetworkPolicy/alice-85a782e": netpol}))
    classes(inp) == {"open-egress"}
}

test_detect_kind_limits_condition if {
    # a ConfigMap carrying a pod-like field does not match a Pod condition
    cm := object.union(plain_configmap, {"spec": {"hostPID": true}})
    inp := resources_input("alice", object.union(plain_resources, {"ConfigMap/alice-85a782e-init": cm}))
    classes(inp) == set()
}

test_detect_classes_combine_with_roles if {
    inp := pod_input("erin", [{"op": "add", "path": "/spec/hostNetwork", "value": true}])
    detect_obligation(inp) == "container-escape,crypto,exfil,lateral-movement-and-network"
}

test_detect_all_condition if {
    cls := {"privileged-host-network": {
        "all": [
            {"kind": "Pod", "path": "spec.hostNetwork", "equals": true},
            {"kind": "Pod", "path": "spec.containers.*.securityContext.privileged", "equals": true},
        ],
        "categories": {"all"},
    }}
    net := pod_input("alice", [{"op": "add", "path": "/spec/hostNetwork", "value": true}])
    data.threat.obligations.detect == "none" with input as net with data.threat.detect_classes as cls with enrich.user as mock_enrich_user
    both := pod_input("alice", [
        {"op": "add", "path": "/spec/hostNetwork", "value": true},
        {"op": "add", "path": "/spec/containers/0/securityContext/privileged", "value": true},
    ])
    data.threat.obligations.detect == "all" with input as both with data.threat.detect_classes as cls with enrich.user as mock_enrich_user
}

test_detect_prefix_condition if {
    cls := {"untrusted-image": {"any": [{"kind": "Pod", "path": "spec.containers.*.image", "prefix": "docker.io/"}], "categories": {"cryptomining"}}}
    inp := pod_input("alice", [{"op": "replace", "path": "/spec/containers/0/image", "value": "docker.io/foo:1"}])
    data.threat.obligations.detect == "cryptomining" with input as inp with data.threat.detect_classes as cls with enrich.user as mock_enrich_user
    data.threat.obligations.detect == "none" with input as pod_input("alice", []) with data.threat.detect_classes as cls with enrich.user as mock_enrich_user
}

test_detect_rule_by_class if {
    rules := [{"org": "acme", "class": "host-network", "categories": {"all"}}]
    inp := pod_input("alice", [{"op": "add", "path": "/spec/hostNetwork", "value": true}])
    data.threat.obligations.detect == "all" with input as inp with data.threat.detect_rules as rules with enrich.user as mock_enrich_user
    data.threat.obligations.detect == "none" with input as pod_input("alice", []) with data.threat.detect_rules as rules with enrich.user as mock_enrich_user
}

test_detect_undecodable_resources_has_no_class if {
    inp := json.patch(detect_input("alice"), [{"op": "add", "path": "/context/resources", "value": "{not json"}])
    classes(inp) == set()
    threat_allowed(inp)
}

# --- threat:detect never gates access for a valid request ---

test_detect_allowed_for_any_valid_request if {
    every who in {"alice", "bob", "carol", "root"} {
        threat_allowed(detect_input(who))
        threat_allowed(inject_input(who))
    }
}

# --- malformed threat:detect input is rejected ---

test_detect_unknown_mode_rejected if {
    inp := json.patch(detect_input("root"), [{"op": "replace", "path": "/context/mode", "value": "sidecar"}])
    not threat_allowed(inp)
}

test_detect_missing_namespace_rejected if not threat_allowed(json.remove(detect_input("root"), ["context/namespace"]))

test_detect_inject_missing_workload_rejected if {
    not threat_allowed(json.remove(inject_input("root"), ["context/workload_name"]))
    not threat_allowed(json.remove(inject_input("root"), ["context/workload_kind"]))
}

test_detect_missing_id_rejected if not threat_allowed(json.remove(detect_input("alice"), ["resource/id"]))

test_detect_missing_owner_rejected if not threat_allowed(json.remove(detect_input("alice"), ["resource/attributes/owner"]))

test_detect_non_workspace_resource_rejected if {
    inp := json.patch(detect_input("alice"), [{"op": "replace", "path": "/resource/type", "value": "user"}])
    not threat_allowed(inp)
}

# --- threat:detection:override ---

test_override_plain_user_cannot_override_own if not threat_allowed(override_input("alice", "alice"))

test_override_plain_user_cannot_override_other if not threat_allowed(override_input("alice", "carol"))

test_override_detect_role_does_not_grant_override if not threat_allowed(override_input("dave", "alice"))

test_override_group_admin_overrides_group_user if {
    threat_allowed(override_input("bob", "alice"))
    threat_allowed(override_probe("bob", "alice"))
}

test_override_group_admin_cannot_override_other_group if not threat_allowed(override_input("bob", "gina"))

test_override_group_admin_cannot_override_other_org if not threat_allowed(override_input("bob", "carol"))

test_override_group_admin_cannot_override_site_admin if not threat_allowed(override_input("bob", "root"))

test_override_group_admin_cannot_override_own if not threat_allowed(override_input("bob", "bob"))

test_override_org_admin_overrides_any_group_in_org if {
    threat_allowed(override_input("orga", "alice"))
    threat_allowed(override_input("orga", "gina"))
    threat_allowed(override_input("orga", "bob"))
    threat_allowed(override_probe("orga", "gina"))
}

test_override_org_admin_overrides_own if {
    threat_allowed(override_input("orga", "orga"))
    threat_allowed(override_probe("orga", "orga"))
}

test_override_org_admin_cannot_override_other_org if not threat_allowed(override_input("orga", "carol"))

test_override_admin_overrides_everything if {
    threat_allowed(override_input("root", "carol"))
    threat_allowed(override_input("root", "root"))
    threat_allowed(override_probe("root", "carol"))
}

test_override_no_obligations if {
    inp := override_input("bob", "alice")
    data.threat.obligations == {} with input as inp with enrich.user as mock_enrich_user
}

# --- detect reason ---

detect_reason(inp) := r if {
    r := data.threat.reason with input as inp with enrich.user as mock_enrich_user
}

test_detect_reason_is_not_an_obligation if {
    not "detect_reason" in object.keys(data.threat.obligations) with input as detect_input("erin") with enrich.user as mock_enrich_user
}

test_detect_reason_nothing_matched if {
    detect_reason(pod_input("alice", [])) == "no detect role, rule or class matched"
}

test_detect_reason_roles if detect_reason(detect_input("erin")) == "role detect-crypto; role detect-exfil"

test_detect_reason_class_names_matched_condition if {
    inp := pod_input("alice", [{"op": "add", "path": "/spec/containers/0/securityContext/privileged", "value": true}])
    detect_reason(inp) == `class privileged: container-escape,privilege-escalation-and-kernel ({"equals":true,"kind":"Pod","path":"spec.containers|initContainers.*.securityContext.privileged"})`
}

test_detect_reason_sudo if {
    detect_reason(pod_input("sam", [])) == "class sudo: privilege-escalation-and-kernel (owner sam has sudo)"
}

test_detect_reason_rule if {
    rules := [{"org": "acme", "blueprint": "default", "categories": {"exfil"}}]
    r := data.threat.reason with input as detect_input("alice") with data.threat.detect_rules as rules with enrich.user as mock_enrich_user
    r == `rule {"blueprint":"default","org":"acme"}: exfil`
}

test_detect_reason_combines_sources if {
    inp := pod_input("erin", [{"op": "add", "path": "/spec/hostNetwork", "value": true}])
    detect_reason(inp) == `class host-network: container-escape,lateral-movement-and-network ({"equals":true,"kind":"Pod","path":"spec.hostNetwork"}); role detect-crypto; role detect-exfil`
}

# --- threat:list ---

list_input(who) := {
    "action": "threat:list",
    "subject": subject(who),
    "resource": {"type": "threat"},
    "context": {},
}

list_obligations(who) := ob if {
    ob := data.threat.obligations with input as list_input(who) with enrich.user as mock_enrich_user
}

test_list_admin_allowed_unscoped if {
    threat_allowed(list_input("root"))
    not "org" in object.keys(list_obligations("root"))
}

test_list_org_admin_allowed_scoped_to_own_org if {
    threat_allowed(list_input("orga"))
    list_obligations("orga").org == "acme"
}

test_list_group_admin_denied if not threat_allowed(list_input("bob"))

test_list_plain_user_denied if not threat_allowed(list_input("alice"))

test_list_detect_role_does_not_grant_list if not threat_allowed(list_input("dave"))
