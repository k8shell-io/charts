package session

import rego.v1
import data.common

# a <group>-admin can list sessions of users with role <group>-user, for
# every group they administer (scoped via the "roles" obligation below); when
# checked against a specific resource (e.g. a capability check), that
# resource's owner must resolve to an actual managed <group>-user account —
# a nonexistent or unmanaged owner must not pass
allow if {
    input.action == "session:list"
    count(common.group_admin_roles(input.subject.roles)) > 0
    not input.resource.attributes.owner
}

allow if {
    input.action == "session:list"
    owner := input.resource.attributes.owner
    owner
    common.managed_by_group_admin(input.subject, enrich.user(owner))
}

# a user who is not a group admin can list only their own sessions when no
# specific owner is requested (scoped via the "username" obligation below)
allow if {
    input.action == "session:list"
    count(common.group_admin_roles(input.subject.roles)) == 0
    not input.resource.attributes.owner
}

# a subject can always list their own sessions, regardless of any
# <group>-admin role they also hold — a <group>-admin's own account is never
# a "managed" account (common.managed_by_group_admin requires the target to
# hold the matching "-user" role), so without this rule a <group>-admin's
# self-owned capability check would fall through every rule above and deny
allow if {
    input.action == "session:list"
    input.resource.attributes.owner == input.subject.username
}

# --- session:list obligations ---

# a <group>-admin's listing is scoped to <group>-admin and <group>-user
# accounts, for every group they administer; an org-admin sees every role
# within their organization and is left unscoped here
obligations["roles"] := scoped_roles if {
    input.action == "session:list"
    admin_roles := common.group_admin_roles(input.subject.roles)
    count(admin_roles) > 0
    not common.is_org_admin(input.subject)
    scoped_roles := admin_roles | {managed_role |
        some admin_role in admin_roles
        managed_role := sprintf("%s-user", [trim_suffix(admin_role, "-admin")])
    }
}

# a non-admin's listing is always scoped to their own organization
obligations["org"] := input.subject.org if {
    input.action == "session:list"
    not common.is_admin(input.subject)
}

# a non-group-admin's listing is scoped to their own sessions only
obligations["username"] := input.subject.username if {
    input.action == "session:list"
    count(common.group_admin_roles(input.subject.roles)) == 0
    not common.is_admin(input.subject)
}
