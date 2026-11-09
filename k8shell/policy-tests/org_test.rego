package org_test

import rego.v1
import data.org

node_write(subject) := {
    "action": "org:node:write",
    "resource": {"type": "org", "id": "default"},
    "subject": subject,
}

test_admin_node_write_allowed if {
    org.allow with input as node_write({"username": "a", "roles": ["admin"]})
}

test_org_admin_node_write_denied if {
    not org.allow with input as node_write({"username": "o", "org": "default", "roles": ["org-admin"]})
}

test_user_node_write_denied if {
    not org.allow with input as node_write({"username": "u", "org": "default", "roles": ["developer"]})
}
