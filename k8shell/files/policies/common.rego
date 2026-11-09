package common

import rego.v1

is_admin(subject) if "admin" in subject.roles

# true if subject is an org-admin: able to perform any action a <group>-admin
# of their own organization could perform, across every group in that org
is_org_admin(subject) if "org-admin" in subject.roles

# roles the subject holds that follow the "<group>-admin" convention; a
# subject may administer more than one group
group_admin_roles(roles) := {role |
    some role in roles
    endswith(role, "-admin")
}

# a full site admin's account is off limits to org-admin/<group>-admin
# management entirely, even within their own org — only another full site
# admin may read or write it
protected_admin(target_user) if "admin" in target_user.roles

# true if subject is a <group>-admin managing target_user's account: both
# belong to the same organization and target_user holds the matching
# <group>-user role
managed_by_group_admin(subject, target_user) if {
    admin_roles := group_admin_roles(subject.roles)
    count(admin_roles) > 0
    subject.org == target_user.organization
    not protected_admin(target_user)
    some admin_role in admin_roles
    managed_role := sprintf("%s-user", [trim_suffix(admin_role, "-admin")])
    managed_role in target_user.roles
}

# a <group>-admin also manages the account of a peer <group>-admin — someone
# else holding the same <group>-admin role — so, e.g., two arc-admins can
# reach each other's owner-scoped resources (workspaces included) the same
# way an arc-admin already reaches an arc-user's
managed_by_group_admin(subject, target_user) if {
    admin_roles := group_admin_roles(subject.roles)
    count(admin_roles) > 0
    subject.org == target_user.organization
    not protected_admin(target_user)
    subject.username != target_user.username
    some admin_role in admin_roles
    admin_role in target_user.roles
}

# an org-admin manages every user in their own organization, regardless of
# which <group>-user role that user holds
managed_by_group_admin(subject, target_user) if {
    is_org_admin(subject)
    subject.org == target_user.organization
    not protected_admin(target_user)
}

# inject_role is the role that allows inject mode (workspace:create and
# workspace:provision with context.mode == "inject"): attaching a workspace
# to an existing workload is a higher-trust operation than a standalone
# workspace, so it is gated to a role rather than open to everyone
inject_role := "developer"

# git_workspace_role is the role that gives a user of an external identity
# provider access to its repository catalog (user:read data_type=repos) and
# git-sourced workspaces; which users get it is decided by the onboarding
# rules of the identity providers, not by the policies
git_workspace_role := "git-workspace"

# true if user was onboarded through an external identity provider
# ("idp.k8shell.io/<provider>", not identity's own user file) and holds the
# git_workspace_role; providers without a repository catalog simply have
# none to browse
onboarded_via_git_idp(user) if {
    startswith(user.source, "idp.k8shell.io/")
    user.source != "idp.k8shell.io/file"
    git_workspace_role in user.roles
}
