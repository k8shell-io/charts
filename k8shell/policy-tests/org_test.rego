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

quota_write(subject) := {
    "action": "org:quota:write",
    "resource": {"type": "org", "id": "default"},
    "subject": subject,
}

test_admin_quota_write_allowed if {
    org.allow with input as quota_write({"username": "a", "roles": ["admin"]})
}

test_org_admin_quota_write_denied if {
    not org.allow with input as quota_write({"username": "o", "org": "default", "roles": ["org-admin"]})
}

test_user_quota_write_denied if {
    not org.allow with input as quota_write({"username": "u", "org": "default", "roles": ["developer"]})
}

test_org_admin_reads_own_org if {
    org.allow with input as {
        "action": "org:read",
        "resource": {"type": "org", "id": "default"},
        "subject": {"username": "o", "org": "default", "roles": ["org-admin"]},
    }
}
