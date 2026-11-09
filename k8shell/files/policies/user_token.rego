package user

import rego.v1
import data.common

# users can read/write/delete their own tokens
allow if {
    input.action in {"token:read", "token:write", "token:delete"}
    input.subject.username == input.resource.id
}

# an org-admin can read/write/delete tokens of any user within their own
# organization; a full site admin's tokens are off limits even here — token
# access is equivalent to impersonation, so this is guarded the same way as
# user:delete and the roles data type — see common.protected_admin
allow if {
    input.action in {"token:read", "token:write", "token:delete"}
    common.is_org_admin(input.subject)
    target_user := enrich.user(input.resource.id)
    input.subject.org == target_user.organization
    not common.protected_admin(target_user)
}

# a <group>-admin can read/write/delete tokens of their managed <group>-user accounts
allow if {
    input.action in {"token:read", "token:write", "token:delete"}
    common.managed_by_group_admin(input.subject, enrich.user(input.resource.id))
}
