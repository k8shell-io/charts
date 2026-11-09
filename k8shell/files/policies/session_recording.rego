package session

import rego.v1
import data.common

# session:recording:read follows session:list (session_list.rego) for admins:
# admins read everything, org-admins read recordings of users in their
# organization, <group>-admins read recordings of users they manage. Unlike
# session:list, a plain user (no admin role) cannot read any recordings,
# including their own. It is a separate permission — being able to list sessions
# does not imply being able to read what was recorded in them. One action
# covers every recording type and format.

# a <group>-admin (org-admins included) can read recordings across users when
# no specific owner is requested; the result is scoped via the obligations below
allow if {
    input.action == "session:recording:read"
    count(common.group_admin_roles(input.subject.roles)) > 0
    not input.resource.attributes.owner
}

# when checked against a specific owner, that owner must resolve to an account
# the subject manages (org-admin: same org; <group>-admin: same org and group)
# — a nonexistent or unmanaged owner must not pass
allow if {
    input.action == "session:recording:read"
    owner := input.resource.attributes.owner
    owner
    common.managed_by_group_admin(input.subject, enrich.user(owner))
}

# a <group>-admin can always read their own recordings (their own account is
# never a "managed" account; full admins are covered by the admin rule in
# session_record.rego); a plain user gets no rule and so cannot read
# recordings at all, not even their own
allow if {
    input.action == "session:recording:read"
    count(common.group_admin_roles(input.subject.roles)) > 0
    input.resource.attributes.owner == input.subject.username
}

# a session-recorder can read their own recordings, and browse with no owner
# given, scoped to their own via the username obligation below. A subject who
# also holds a <group>-admin role is covered by the rules above instead.
allow if {
    input.action == "session:recording:read"
    "session-recorder" in input.subject.roles
    input.resource.attributes.owner == input.subject.username
}

allow if {
    input.action == "session:recording:read"
    "session-recorder" in input.subject.roles
    count(common.group_admin_roles(input.subject.roles)) == 0
    not input.resource.attributes.owner
}

# --- session:recording:read obligations ---

# a <group>-admin is scoped to <group>-admin and <group>-user accounts, for
# every group they administer; an org-admin is left unscoped here and bounded
# by the org obligation instead
obligations["roles"] := scoped_roles if {
    input.action == "session:recording:read"
    admin_roles := common.group_admin_roles(input.subject.roles)
    count(admin_roles) > 0
    not common.is_org_admin(input.subject)
    scoped_roles := admin_roles | {managed_role |
        some admin_role in admin_roles
        managed_role := sprintf("%s-user", [trim_suffix(admin_role, "-admin")])
    }
}

# everyone except a full admin is scoped to their own organization
obligations["org"] := input.subject.org if {
    input.action == "session:recording:read"
    not common.is_admin(input.subject)
}

# a session-recorder without any <group>-admin role is scoped to their own
# recordings only
obligations["username"] := input.subject.username if {
    input.action == "session:recording:read"
    "session-recorder" in input.subject.roles
    count(common.group_admin_roles(input.subject.roles)) == 0
    not common.is_admin(input.subject)
}
