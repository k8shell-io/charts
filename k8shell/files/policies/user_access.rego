package user

import rego.v1
import data.common

# users can read their own data (any data type except repos, which needs a
# git-based IdP account behind it — see the repos-specific rule below)
allow if {
    input.action == "user:read"
    input.subject.username == input.resource.id
    input.context.data_type != "repos"
}

# repos is the identity-provider repository catalog, so a self-read only
# makes sense (and is only allowed) when the user was onboarded through one
# an external identity provider with the git-workspace role (see
# common.onboarded_via_git_idp)
allow if {
    input.action == "user:read"
    input.subject.username == input.resource.id
    input.context.data_type == "repos"
    common.onboarded_via_git_idp(input.subject)
}

# data types an owning user may write on their own record — least privilege:
# only the data types with no admin/security implications; "credentials"
# is handled separately below since it needs credential_type-aware scoping.
# "envvars" is included here but deliberately omitted from
# group_admin_editable_data_types below — see the envvars deny rule near the
# bottom of this file. "logins" is included here too, but unlike envvars it
# is *also* in group_admin_editable_data_types below, since org-admins and
# <group>-admins may revoke a managed user's sessions, not just their own
self_editable_data_types := {"profile", "password", "keys", "envvars", "logins"}

allow if {
    input.action == "user:write"
    input.subject.username == input.resource.id
    input.context.data_type in self_editable_data_types
}

# a user may write their own git/registry credentials, but never their own
# kubernetes credentials — kubernetes credential writes are reserved for full
# site admins only, even on the admin's own account (see the admin bypass in
# user.rego); with no allow rule covering a self-write of kubernetes creds,
# it falls through to the default deny for everyone else, org-admins and
# <group>-admins included
allow if {
    input.action == "user:write"
    input.subject.username == input.resource.id
    input.context.data_type == "credentials"
    input.context.credential_type in {"git", "registry"}
}

# a <group>-admin manages other users' accounts, never their own — self-edits
# always go through the self-write rule above, which is intentionally more
# restrictive (e.g. it never grants "roles", "sudo", "locked", or "org").
# repos is excluded here too, same reasoning as the self-read rule above.
allow if {
    input.action == "user:read"
    input.subject.username != input.resource.id
    input.context.data_type != "repos"
    common.managed_by_group_admin(input.subject, enrich.user(input.resource.id))
}

# a <group>-admin may browse a managed user's repos catalog, but only if that
# managed user actually has one — see common.onboarded_via_git_idp
allow if {
    input.action == "user:read"
    input.subject.username != input.resource.id
    input.context.data_type == "repos"
    target_user := enrich.user(input.resource.id)
    common.managed_by_group_admin(input.subject, target_user)
    common.onboarded_via_git_idp(target_user)
}

# data types a <group>-admin may write on their managed users' accounts; org
# is omitted, so only a full site admin (user.rego) can ever write it, keys
# is omitted — see the sshkey deny rule below, which locks key writes to the
# owning user only, the same as token:create — and credentials is omitted
# since it needs credential_type-aware scoping, handled separately below.
# "logins" is included — an org-admin/<group>-admin revoking a managed
# user's login session is the same data_type as a self-revoke, decided here
# by policy rather than a separate contract (see the contract comment on
# user:write's logins data_type)
group_admin_editable_data_types := {
    "profile", "password", "blueprints", "sudo", "locked", "logins"
}

allow if {
    input.action == "user:write"
    input.subject.username != input.resource.id
    input.context.data_type in group_admin_editable_data_types
    common.managed_by_group_admin(input.subject, enrich.user(input.resource.id))
}

# common.managed_by_group_admin covers both org-admins (any user in their
# org) and <group>-admins (their managed <group>-user accounts) — either may
# write git/registry credentials for a user they manage, but never that
# user's kubernetes credentials; kubernetes credential writes stay reserved
# for full site admins only (user.rego's admin bypass)
allow if {
    input.action == "user:write"
    input.subject.username != input.resource.id
    input.context.data_type == "credentials"
    input.context.credential_type in {"git", "registry"}
    common.managed_by_group_admin(input.subject, enrich.user(input.resource.id))
}

# an org-admin may edit roles on any user within their own organization;
# plain <group>-admins cannot — role changes are reserved for org-wide admins.
# A full site admin's own roles are still off limits, even to an org-admin in
# the same org — see common.protected_admin.
allow if {
    input.action == "user:write"
    input.subject.username != input.resource.id
    input.context.data_type == "roles"
    common.is_org_admin(input.subject)
    target_user := enrich.user(input.resource.id)
    input.subject.org == target_user.organization
    not common.protected_admin(target_user)
}

# a <group>-admin can list users (scoped to <group>-user accounts via the
# "roles" obligation below)
allow if {
    input.action == "user:list"
    count(common.group_admin_roles(input.subject.roles)) > 0
}

# a <group>-admin's listing is scoped to <group>-admin and <group>-user
# accounts only, unless they're also a full site admin or an org-admin (who
# sees every role within their organization)
obligations["roles"] := scoped_roles if {
    input.action == "user:list"
    admin_roles := common.group_admin_roles(input.subject.roles)
    count(admin_roles) > 0
    not common.is_admin(input.subject)
    not common.is_org_admin(input.subject)
    scoped_roles := admin_roles | {managed_role |
        some admin_role in admin_roles
        managed_role := sprintf("%s-user", [trim_suffix(admin_role, "-admin")])
    }
}

# a <group>-admin's listing is further scoped to their own organization
obligations["org"] := input.subject.org if {
    input.action == "user:list"
    not common.is_admin(input.subject)
}

# ssh public keys can only ever be written by the owning user — same rule as
# token:create. group_admin_editable_data_types already omits "keys" so
# <group>-admins are covered, but a full site admin still bypasses data_type
# checks entirely via the admin rule in user.rego, so this deny closes that
# gap explicitly rather than carving "user:write" out of admin_denied_actions
# wholesale (which would also block admins from writing roles/sudo/locked/org)
deny if {
    input.action == "user:write"
    input.context.data_type == "keys"
    input.subject.username != input.resource.id
}

# environment variables can only ever be written by the owning user — same
# reasoning as "keys" above. Full site admins, org-admins, and <group>-admins
# may still read another user's envvars (covered by the generic user:read
# rules above, which don't restrict by data_type), but writes stay
# self-service only; group_admin_editable_data_types already omits "envvars"
# so <group>-admins/org-admins are covered, and this deny closes the same
# full-site-admin bypass gap as the "keys" deny
deny if {
    input.action == "user:write"
    input.context.data_type == "envvars"
    input.subject.username != input.resource.id
}

# locked status can only ever be written on another user's account — never on
# the subject's own. self_editable_data_types and group_admin_editable_data_types
# already keep the specific write rules above from granting a self-write of
# "locked", but a full site admin still bypasses data_type checks entirely via
# the admin rule in user.rego, which would otherwise let an admin unlock (or
# lock) their own account; this deny closes that gap explicitly, the same as
# the "keys" deny above
deny if {
    input.action == "user:write"
    input.context.data_type == "locked"
    input.subject.username == input.resource.id
}
