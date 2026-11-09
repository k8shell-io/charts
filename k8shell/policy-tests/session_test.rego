package session_test

import rego.v1

# --- fixtures ---

users := {
    "alice": {"username": "alice", "organization": "acme", "roles": ["dev-user"]},
    "bob": {"username": "bob", "organization": "acme", "roles": ["dev-admin"]},
    "carol": {"username": "carol", "organization": "other", "roles": ["dev-user"]},
    "root": {"username": "root", "organization": "acme", "roles": ["admin"]},
    "dave": {"username": "dave", "organization": "acme", "roles": ["dev-user",
        "record-shell", "record-tcpip", "record-exec", "record-sftp"]},
    "erin": {"username": "erin", "organization": "acme", "roles": ["dev-user", "record-shell"]},
    "auditor": {"username": "auditor", "organization": "acme", "roles": ["admin", "record-exec"]},
    "frank": {"username": "frank", "organization": "tul-fm", "roles": ["dev-user"]},
}

subject(name) := {
    "username": name,
    "org": users[name].organization,
    "roles": users[name].roles,
}

mock_enrich_user(name) := users[name]

record_input(action, who, owner, session_type, session_source) := {
    "action": action,
    "subject": subject(who),
    "resource": {"type": "workspace", "id": "ws1", "attributes": {"owner": owner, "blueprint": "default"}},
    "context": {"session_type": session_type, "session_source": session_source},
}

entry_input(action, who, owner) := {
    "action": action,
    "subject": subject(who),
    "resource": {"type": "workspace", "id": "ws1", "attributes": {"owner": owner}},
    "context": {},
}

# every session_type/session_source combination the contract allows
record_cases := {[t, s] |
    some t in {"shell", "tcpip", "exec", "sftp"}
    some s in {"ssh-proxy", "api-server"}
}

ssh_entry_actions := {"ssh:shell", "ssh:exec", "ssh:sftp", "ssh:direct-tcpip",
    "ssh:direct-streamlocal", "ssh:agent-forward"}

# a decision is allowed when allow holds and no deny fires, as the authz
# service evaluates it
session_allowed(inp) if {
    data.session.allow with input as inp with enrich.user as mock_enrich_user
    not data.session.deny with input as inp with enrich.user as mock_enrich_user
}

ssh_allowed(inp) if {
    data.ssh.allow with input as inp
    not data.ssh.deny with input as inp
}

workspace_allowed(inp) if {
    data.workspace.allow with input as inp with enrich.user as mock_enrich_user
    not data.workspace.deny with input as inp with enrich.user as mock_enrich_user
}

record_obligation(inp) := ob if {
    ob := data.session.obligations.record with input as inp with enrich.user as mock_enrich_user
}

# --- record obligation ---

expected_channels := {"shell": "shell", "tcpip": "direct-tcpip,vscode-terminals,vscode-input", "exec": "exec", "sftp": "sftp"}

test_record_obligation_records_channel_with_matching_role if {
    every c in record_cases {
        record_obligation(record_input("session:record", "dave", "alice", c[0], c[1])) == expected_channels[c[0]]
    }
}

test_record_obligation_none_without_any_record_role if {
    every who in {"alice", "bob", "carol", "root"} {
        every c in record_cases {
            record_obligation(record_input("session:record", who, "alice", c[0], c[1])) == "none"
        }
    }
}

# a record-<type> role covers only that session_type
test_record_obligation_only_for_session_type_of_held_role if {
    every c in record_cases {
        expected := {true: "shell", false: "none"}[c[0] == "shell"]
        record_obligation(record_input("session:record", "erin", "alice", c[0], c[1])) == expected
    }
}

# admin status neither forces nor suppresses recording; only the role counts
test_record_obligation_admin_with_record_role if {
    record_obligation(record_input("session:record", "auditor", "alice", "exec", "ssh-proxy")) == "exec"
    record_obligation(record_input("session:record", "auditor", "alice", "shell", "ssh-proxy")) == "none"
}

# --- session:record never gates access for a valid request ---

test_session_record_allowed_for_any_valid_request if {
    every who in object.keys(users) {
        every c in record_cases {
            session_allowed(record_input("session:record", who, "alice", c[0], c[1]))
        }
    }
}

# --- malformed session:record input is rejected ---

test_session_record_unknown_session_type_rejected if {
    every who in {"alice", "root"} {
        not session_allowed(record_input("session:record", who, "alice", "x11", "api-server"))
    }
}

test_session_record_unknown_session_source_rejected if {
    every who in {"alice", "root"} {
        not session_allowed(record_input("session:record", who, "alice", "shell", "browser"))
    }
}

test_session_record_missing_id_rejected if {
    inp := json.remove(record_input("session:record", "alice", "alice", "shell", "api-server"), ["resource/id"])
    not session_allowed(inp)
}

test_session_record_missing_owner_rejected if {
    inp := json.remove(record_input("session:record", "alice", "alice", "shell", "api-server"), ["resource/attributes/owner"])
    not session_allowed(inp)
}

test_session_record_non_workspace_resource_rejected if {
    inp := json.patch(record_input("session:record", "alice", "alice", "shell", "api-server"),
        [{"op": "replace", "path": "/resource/type", "value": "user"}])
    not session_allowed(inp)
}

# --- access is gated at the entry rules, not session:record ---

test_unrelated_user_denied_at_ssh_entry_rules if {
    every action in ssh_entry_actions {
        not ssh_allowed(entry_input(action, "carol", "alice"))
    }
}

test_unrelated_user_denied_at_workspace_connect if {
    not workspace_allowed(entry_input("workspace:connect", "carol", "alice"))
}

test_owner_allowed_at_entry_rules if {
    every action in ssh_entry_actions {
        ssh_allowed(entry_input(action, "alice", "alice"))
    }
    workspace_allowed(entry_input("workspace:connect", "alice", "alice"))
}

test_group_admin_allowed_at_workspace_connect if {
    workspace_allowed(entry_input("workspace:connect", "bob", "alice"))
}

# ssh:* admits only admins and owners — a <group>-admin can reach a managed
# user's workspace via workspace:connect but not over ssh
test_group_admin_denied_at_ssh_entry_rules if {
    every action in ssh_entry_actions {
        not ssh_allowed(entry_input(action, "bob", "alice"))
    }
}

# --- record_rules: recording by org and blueprint ---

with_blueprint(inp, bp) := json.patch(inp, [{"op": "replace", "path": "/resource/attributes/blueprint", "value": bp}])

test_record_obligation_org_blueprint_rule if {
    every c in record_cases {
        inp := with_blueprint(record_input("session:record", "frank", "frank", c[0], c[1]), "ct1")
        record_obligation(inp) == expected_channels[c[0]]
    }
}

test_record_obligation_org_rule_other_blueprint if {
    every c in record_cases {
        record_obligation(record_input("session:record", "frank", "frank", c[0], c[1])) == "none"
    }
}

test_record_obligation_org_rule_missing_blueprint if {
    inp := json.remove(record_input("session:record", "frank", "frank", "shell", "ssh-proxy"), ["resource/attributes/blueprint"])
    record_obligation(inp) == "none"
}

test_record_obligation_blueprint_rule_other_org if {
    every c in record_cases {
        inp := with_blueprint(record_input("session:record", "alice", "alice", c[0], c[1]), "ct1")
        record_obligation(inp) == "none"
    }
}
