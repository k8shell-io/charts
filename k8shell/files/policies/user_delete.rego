package user

import rego.v1
import data.common

# admins can delete any user account except their own
allow if {
    input.action == "user:delete"
    common.is_admin(input.subject)
    input.subject.username != input.resource.id
}

# an org-admin can delete user accounts within their own organization, but
# never their own account; a full site admin's account is off limits even
# here — see common.protected_admin
allow if {
    input.action == "user:delete"
    common.is_org_admin(input.subject)
    input.subject.username != input.resource.id
    target_user := enrich.user(input.resource.id)
    input.subject.org == target_user.organization
    not common.protected_admin(target_user)
}

# no subject may ever delete their own account. The two allow rules above
# already require subject != resource, but a full site admin still bypasses
# those checks entirely via the admin rule in user.rego (user:delete is not
# in admin_denied_actions), which would otherwise let an admin delete their
# own account; this deny closes that gap explicitly, mirroring the "locked"
# self-write deny in user_access.rego
deny if {
    input.action == "user:delete"
    input.subject.username == input.resource.id
}
