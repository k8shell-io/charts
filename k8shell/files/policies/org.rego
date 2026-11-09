package org

import rego.v1
import data.common

default allow := false

# admins can perform any org action; role/user-scoped access (e.g. an
# org-admin managing their own org) is not yet defined here
allow if {
    input.action in {
        "org:list", "org:create", "org:delete", "org:update", "org:read",
        "org:envvar:read", "org:envvar:write", "org:node:write",
    }
    common.is_admin(input.subject)
}

# org:node:write (replacing an org's node selectors and listing the node
# selector options, which expose cluster topology) is deliberately absent from
# the org-admin rule below: it is kept off org:update so an org-admin cannot
# steer their org's workspaces onto particular nodes

# org-admins can read or update their own org, including its environment
# variables (org:envvar:read/write is kept separate from org:read/update — see
# the contract docs in this file — but an org-admin gets both the same way)
allow if {
    input.action in {"org:read", "org:update", "org:envvar:read", "org:envvar:write"}
    common.is_org_admin(input.subject)
    input.resource.id == input.subject.org
}

# org-admins can list orgs, scoped to their own org via the "orgs" obligation
# below
allow if {
    input.action == "org:list"
    common.is_org_admin(input.subject)
}

# --- org:list obligations ---

# an org-admin's listing is scoped to the single org they're a member of;
# full admins are exempt since they can see every org
obligations["org"] := input.subject.org if {
    input.action == "org:list"
    common.is_org_admin(input.subject)
    not common.is_admin(input.subject)
}
