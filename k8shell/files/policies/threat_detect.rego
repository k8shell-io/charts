package threat

import rego.v1
import data.common

default allow := false

# admins can perform any threat action
allow if common.is_admin(input.subject)

# --- threat:detect ---

# threat:detect decides which attack categories worktrace watches on a
# workspace; it is not an access check. The provisioner evaluates it when it
# provisions a workspace and consumes only the obligations, never allowed — so
# any well-formed request is allowed here.
allow if input.action == "threat:detect"

# a malformed threat:detect request is rejected, regardless of admin status
deny if {
    input.action == "threat:detect"
    not valid_detect_input
}

valid_detect_input if {
    input.resource.type == "workspace"
    input.resource.id != ""
    input.resource.attributes.owner != ""
    input.context.namespace != ""
    valid_detect_mode
}

valid_detect_mode if input.context.mode == "standalone"

valid_detect_mode if {
    input.context.mode == "inject"
    input.context.workload_name != ""
    input.context.workload_kind != ""
}

# --- threat:detect obligations ---

# detect the categories granted by the subject's detect-<category> roles
# (detect-all for every category) and by matching detect_rules entries; the
# obligation value lists them comma-separated, or "all" when any grant is "all"
obligations["detect"] := "all" if {
    input.action == "threat:detect"
    "all" in detect_categories
}

obligations["detect"] := concat(",", sort(detect_categories)) if {
    input.action == "threat:detect"
    count(detect_categories) > 0
    not "all" in detect_categories
}

# explicitly disable detection for everyone else, rather than leaving it to
# the enforcer's default (worktrace's global rule rollout)
obligations["detect"] := "none" if {
    input.action == "threat:detect"
    count(detect_categories) == 0
}

detect_categories contains category if {
    some role in input.subject.roles
    startswith(role, "detect-")
    category := trim_prefix(role, "detect-")
    category != ""
}

detect_categories contains category if {
    some rule in matched_rules
    some category in rule.categories
}

detect_categories contains category if {
    some class in detection_classes
    some category in detect_classes[class].categories
}

# what led to the detect obligation, returned as the decision's reason
# (PolicyResult.Reason): one entry per detect-<category> role, matched
# detect_rules entry and detection class, with the conditions that matched
# the class
reason := concat("; ", sort(detect_reasons)) if {
    input.action == "threat:detect"
    count(detect_reasons) > 0
}

reason := "no detect role, rule or class matched" if {
    input.action == "threat:detect"
    count(detect_reasons) == 0
}

detect_reasons contains sprintf("role %s", [role]) if {
    some role in input.subject.roles
    startswith(role, "detect-")
    trim_prefix(role, "detect-") != ""
}

detect_reasons contains sprintf("rule %s: %s", [json.marshal(object.remove(rule, {"categories"})), concat(",", sort(rule.categories))]) if {
    some rule in matched_rules
}

detect_reasons contains reason if {
    some class in detection_classes
    evidence := {e | some [c, e] in class_evidence; c == class}
    reason := sprintf("class %s: %s (%s)", [
        class,
        concat(",", sort(detect_classes[class].categories)),
        concat(", ", sort(evidence)),
    ])
}

# [class, evidence] pairs: the conditions of each detection class that hold,
# and why the sudo class holds
class_evidence contains [class, json.marshal(cond)] if {
    some class in detection_classes
    spec := detect_classes[class]
    some cond in array.concat(object.get(spec, "any", []), object.get(spec, "all", []))
    resource_condition(cond)
}

class_evidence contains ["sudo", sprintf("owner %s has sudo", [input.resource.attributes.owner])] if owner_has_sudo

matched_rules contains rule if {
    some rule in detect_rules
    object.get(rule, "org", input.subject.org) == input.subject.org
    object.get(rule, "blueprint", blueprint_name) == blueprint_name
    object.get(rule, "class", "") in detection_classes | {""}
}

# workspaces detected regardless of roles, for the listed categories ("all"
# for every category). Each of org, blueprint and class is optional and, when
# set, must match: org the subject's org, blueprint the blueprint name, class
# one of the workspace's detection_classes, e.g.
#   {"org": "tul-fm", "blueprint": "ct1-content", "categories": {"all"}}
#   {"org": "tul-fm", "class": "privileged", "categories": {"all"}}
# (array.concat types the empty default as array[any]; a literal [] has no
# element type and fails type checking where the rules are iterated)
detect_rules := array.concat([], [])

# --- workspace detection classes ---

# the workspace chart as the provisioner renders it, decoded from
# context.resources: an object of Kubernetes documents keyed "Kind/name"
# (Secrets are left out, ConfigMaps carry metadata only). In inject mode it
# holds only what the workspace chart contributes, not the target workload's
# own containers. Undefined when the caller passed none (or it does not
# decode), in which case no detection class matches.
resources := json.unmarshal(input.context.resources) if is_string(input.context.resources)

default blueprint_name := ""

blueprint_name := input.resource.attributes.blueprint

# detection_classes is the set of detect_classes whose conditions hold on the
# rendered resources. A class holds when any of its "any" conditions holds,
# or every one of its "all" conditions holds (a class may set either, or both).
detection_classes contains class if {
    some class, spec in detect_classes
    some cond in object.get(spec, "any", [])
    resource_condition(cond)
}

detection_classes contains class if {
    some class, spec in detect_classes
    conds := object.get(spec, "all", [])
    count(conds) > 0
    every cond in conds {
        resource_condition(cond)
    }
}

# the workspace owner, not the provisioning subject, is the user k8shelld
# creates in the workspace, so sudo is read from the owner's account
detection_classes contains "sudo" if owner_has_sudo

owner_has_sudo if enrich.user(input.resource.attributes.owner).sudo == true

# resource_condition(cond) holds when some value at cond.path in some rendered
# resource satisfies cond's test. kind optionally limits the resources to that
# kind; without it every resource is searched. path is dot-separated from the
# resource root; a "*" segment matches any map key or list index and "a|b"
# matches either key, e.g. "spec.containers|initContainers.*.image" (kind
# takes "A|B" too). The test is one of:
#   "equals": v    the value is v
#   "in": [v, ...] the value is one of the listed values
#   "prefix": s    the value is a string starting with s
#   "present": true the path exists and its value is not null, false or empty
resource_condition(cond) if {
    some value in resource_values(cond)
    value_test(cond, value)
}

resource_values(cond) := {value |
    pattern := split(cond.path, ".")
    some res in resources
    kind_matches(cond, res)
    walk(res, [p, value])
    count(p) == count(pattern)
    every i, seg in pattern {
        path_segment_matches(seg, p[i])
    }
}

kind_matches(cond, _) if not "kind" in object.keys(cond)

kind_matches(cond, res) if res.kind in split(cond.kind, "|")

path_segment_matches("*", _)

path_segment_matches(seg, key) if sprintf("%v", [key]) in split(seg, "|")

value_test(cond, value) if value == cond.equals

value_test(cond, value) if value in cond["in"]

value_test(cond, value) if {
    is_string(value)
    startswith(value, cond.prefix)
}

value_test(cond, value) if {
    cond.present == true
    not value in {null, false, "", [], {}}
}

# traits of the rendered workspace mapped to the worktrace categories
# (threat.Categories, or "all") watched on workspaces that have them, for
# every subject
detect_classes := {
    # a privileged container, or one granted kernel-level capabilities, can
    # reach the host kernel and devices
    "privileged": {
        "any": [
            {"kind": "Pod", "path": "spec.containers|initContainers.*.securityContext.privileged", "equals": true},
            {
                "kind": "Pod",
                "path": "spec.containers|initContainers.*.securityContext.capabilities.add.*",
                "in": ["ALL", "SYS_ADMIN", "SYS_MODULE", "SYS_PTRACE", "SYS_RAWIO", "DAC_READ_SEARCH", "BPF"],
            },
        ],
        "categories": {"container-escape", "privilege-escalation-and-kernel"},
    },
    # the pod shares the host's process or IPC namespace
    "host-namespaces": {
        "any": [{"kind": "Pod", "path": "spec.hostPID|hostIPC", "equals": true}],
        "categories": {"container-escape", "privilege-escalation-and-kernel"},
    },
    # the pod runs in the host's network namespace
    "host-network": {
        "any": [{"kind": "Pod", "path": "spec.hostNetwork", "equals": true}],
        "categories": {"container-escape", "lateral-movement-and-network"},
    },
    # a host directory is mounted into the pod
    "host-path": {
        "any": [{"kind": "Pod", "path": "spec.volumes.*.hostPath.path", "present": true}],
        "categories": {"container-escape", "persistence"},
    },
    # the workspace user k8shelld creates may sudo (k8shelld itself always
    # runs as root, so the pod's runAsUser tells nothing); matched by
    # owner_has_sudo rather than by resource conditions
    "sudo": {"categories": {"privilege-escalation-and-kernel"}},
    # the chart grants the workspace Kubernetes API permissions
    "cluster-access": {
        "any": [{"kind": "RoleBinding|ClusterRoleBinding", "path": "roleRef.name", "present": true}],
        "categories": {"container-runtime-and-k8s-api", "credential-access", "lateral-movement-and-network"},
    },
    # a network policy opens egress to anywhere
    "open-egress": {
        "any": [{"kind": "NetworkPolicy", "path": "spec.egress.*.to.*.ipBlock.cidr", "in": ["0.0.0.0/0", "::/0"]}],
        "categories": {"lateral-movement-and-network", "reverse-shells-and-execution", "cryptomining"},
    },
}
