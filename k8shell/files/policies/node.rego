package node

import rego.v1
import data.common

default allow := false

# --- node:usage:read ---
#
# The node usage view. Admins see every node and every workspace by name.
# Org-admins and <group>-admins (org-admin is one of them: its role ends in
# "-admin") see the nodes their organization's workspaces may run on, via the
# "org" obligation below; which workspaces they see by name is their
# workspace:list scope, evaluated separately by the gateway.

allow if {
    input.action == "node:usage:read"
    common.is_admin(input.subject)
}

allow if {
    input.action == "node:usage:read"
    count(common.group_admin_roles(input.subject.roles)) > 0
}

# a non-admin's view is limited to their organization's nodes
obligations["org"] := input.subject.org if {
    input.action == "node:usage:read"
    not common.is_admin(input.subject)
}
