package license_test

import rego.v1

license_input(roles) := {
    "action": "license:write",
    "subject": {"username": "alice", "roles": roles, "org": "default"},
    "resource": {"type": "license"},
}

test_admin_writes_the_license if data.license.allow with input as license_input(["admin"])

test_org_admin_does_not_write_the_license if not data.license.allow with input as license_input(["org-admin"])

test_group_admin_does_not_write_the_license if not data.license.allow with input as license_input(["team-admin"])

test_user_does_not_write_the_license if not data.license.allow with input as license_input([])

test_other_actions_are_not_allowed if {
    not data.license.allow with input as object.union(license_input(["admin"]), {"action": "license:read"})
}
