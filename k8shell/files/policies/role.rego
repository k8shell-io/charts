package role

import rego.v1
import data.common

default allow := false

# admins can perform any role action, unscoped; role:list's "org" obligation
# is left unset, which the enforcer treats as no restriction
allow if {
    input.action in {"role:list", "role:create", "role:delete", "role:update"}
    common.is_admin(input.subject)
}

# an org-admin can create, update, or delete roles scoped to their own
# organization
allow if {
    input.action in {"role:create", "role:update", "role:delete"}
    common.is_org_admin(input.subject)
    input.resource.attributes.org == input.subject.org
}

# a <group>-admin can list roles; this also covers org-admin, since
# "org-admin" itself follows the "<group>-admin" convention. The listing is
# scoped to the subject's own org via the "org" obligation below — role:list's
# contract has no per-role-name obligation, so a <group>-admin (e.g.
# am2-admin) sees every role in their org rather than only am2-user/am2-admin
allow if {
    input.action == "role:list"
    count(common.group_admin_roles(input.subject.roles)) > 0
}

# --- role:list obligations ---

# only full admins may also see global (org-less) roles alongside org-scoped
# ones; absent is treated as "false" for everyone else
obligations["global_roles"] := "true" if {
    input.action == "role:list"
    common.is_admin(input.subject)
}

# every non-admin listing (org-admins and <group>-admins alike) is scoped to
# the subject's own organization
obligations["org"] := input.subject.org if {
    input.action == "role:list"
    not common.is_admin(input.subject)
}
