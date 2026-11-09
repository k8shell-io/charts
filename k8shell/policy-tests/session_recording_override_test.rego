package session_test

import rego.v1

# fixtures (users, mock_enrich_user, session_allowed) live in session_test.rego;
# rec_user/rec_subject/rec_enrich in session_recording_test.rego

override_input(who, owner) := {
    "action": "session:recording:override",
    "subject": rec_subject(who),
    "resource": {"type": "workspace", "id": "ws1", "attributes": {"owner": owner}},
    "context": {},
}

override_probe(who, owner) := {
    "action": "session:recording:override",
    "subject": rec_subject(who),
    "resource": {"type": "workspace", "attributes": {"owner": owner}},
    "context": {},
}

override_allowed(inp) if {
    data.session.allow with input as inp with enrich.user as rec_enrich
    not data.session.deny with input as inp with enrich.user as rec_enrich
}

test_override_plain_user_cannot_override_own if not override_allowed(override_input("alice", "alice"))

test_override_plain_user_cannot_override_other if not override_allowed(override_input("alice", "carol"))

test_override_group_admin_overrides_group_user if {
    override_allowed(override_input("bob", "alice"))
    override_allowed(override_probe("bob", "alice"))
}

test_override_group_admin_cannot_override_other_group if not override_allowed(override_input("bob", "gina"))

test_override_group_admin_cannot_override_other_org if not override_allowed(override_input("bob", "carol"))

test_override_group_admin_cannot_override_site_admin if not override_allowed(override_input("bob", "root"))

test_override_group_admin_cannot_override_own if not override_allowed(override_input("bob", "bob"))

test_override_org_admin_overrides_any_group_in_org if {
    override_allowed(override_input("orga", "alice"))
    override_allowed(override_input("orga", "gina"))
    override_allowed(override_input("orga", "bob"))
    override_allowed(override_probe("orga", "gina"))
}

test_override_org_admin_overrides_own if {
    override_allowed(override_input("orga", "orga"))
    override_allowed(override_probe("orga", "orga"))
}

test_override_org_admin_cannot_override_other_org if not override_allowed(override_input("orga", "carol"))

test_override_org_admin_cannot_override_site_admin if not override_allowed(override_input("orga", "root"))

test_override_admin_overrides_everything if {
    override_allowed(override_input("root", "carol"))
    override_allowed(override_input("root", "root"))
    override_allowed(override_probe("root", "carol"))
}

test_override_no_obligations if {
    inp := override_input("bob", "alice")
    data.session.obligations == {} with input as inp with enrich.user as rec_enrich
}

test_override_session_recorder_overrides_own if {
    override_allowed(override_input("rita", "rita"))
    override_allowed(override_probe("rita", "rita"))
}

test_override_session_recorder_cannot_override_other if {
    not override_allowed(override_input("rita", "alice"))
    not override_allowed(override_input("rita", "carol"))
}
