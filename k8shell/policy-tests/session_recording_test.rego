package session_test

import rego.v1

# fixtures (users, subject, mock_enrich_user, session_allowed) live in session_test.rego

rec_users := {
    "orga": {"username": "orga", "organization": "acme", "roles": ["org-admin"]},
    "gina": {"username": "gina", "organization": "acme", "roles": ["ops-user"]},
    "rita": {"username": "rita", "organization": "acme", "roles": ["dev-user", "session-recorder"]},
}

rec_user(name) := object.union(users, rec_users)[name]

rec_subject(name) := {
    "username": name,
    "org": rec_user(name).organization,
    "roles": rec_user(name).roles,
}

rec_enrich(name) := rec_user(name)

rec_input(who, owner) := {
    "action": "session:recording:read",
    "subject": rec_subject(who),
    "resource": {"type": "workspace", "attributes": {"owner": owner}},
    "context": {},
}

rec_input_any(who) := {
    "action": "session:recording:read",
    "subject": rec_subject(who),
    "resource": {"type": "workspace", "attributes": {}},
    "context": {},
}

rec_allowed(inp) if data.session.allow with input as inp with enrich.user as rec_enrich

test_recording_plain_user_cannot_read_own if not rec_allowed(rec_input("alice", "alice"))

test_recording_plain_user_cannot_read_other if not rec_allowed(rec_input("alice", "carol"))

test_recording_plain_user_cannot_list_any if not rec_allowed(rec_input_any("alice"))

test_recording_group_admin_reads_group_user if rec_allowed(rec_input("bob", "alice"))

test_recording_group_admin_cannot_read_other_group if not rec_allowed(rec_input("bob", "gina"))

test_recording_group_admin_cannot_read_other_org if not rec_allowed(rec_input("bob", "carol"))

test_recording_group_admin_cannot_read_site_admin if not rec_allowed(rec_input("bob", "root"))

test_recording_group_admin_reads_own if rec_allowed(rec_input("bob", "bob"))

test_recording_group_admin_scoped_by_roles if {
    inp := rec_input_any("bob")
    data.session.obligations == {"org": "acme", "roles": {"dev-admin", "dev-user"}} with input as inp
}

test_recording_org_admin_reads_any_group_in_org if {
    rec_allowed(rec_input("orga", "alice"))
    rec_allowed(rec_input("orga", "gina"))
}

test_recording_org_admin_cannot_read_other_org if not rec_allowed(rec_input("orga", "carol"))

test_recording_org_admin_scoped_by_org_only if {
    inp := rec_input_any("orga")
    data.session.obligations == {"org": "acme"} with input as inp
}

test_recording_admin_reads_everything if {
    rec_allowed(rec_input("root", "carol"))
    rec_allowed(rec_input_any("root"))
}

test_recording_admin_unscoped if {
    inp := rec_input_any("root")
    data.session.obligations == {} with input as inp
}

test_recording_session_recorder_reads_own if rec_allowed(rec_input("rita", "rita"))

test_recording_session_recorder_cannot_read_other if {
    not rec_allowed(rec_input("rita", "alice"))
    not rec_allowed(rec_input("rita", "carol"))
}

test_recording_session_recorder_lists_scoped_to_own if {
    inp := rec_input_any("rita")
    rec_allowed(inp)
    data.session.obligations == {"org": "acme", "username": "rita"} with input as inp
}
