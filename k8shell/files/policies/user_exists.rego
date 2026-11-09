package user

import rego.v1
import data.common

# Contract: user:exists
#
# Resource  type="user"
#   id   (none) — the check targets an arbitrary, possibly nonexistent,
#        username or email supplied by the caller, not a record the subject
#        already has standing to act on.
#
# Context
#   field  username | email (required) — which identifier is being checked,
#          mirroring FindUserRequest's "exactly one of username or email"
#          contract on the identity side.
#
# Subject   injected by the backend from JWT claims (username, roles, email, ...)
#
# Obligations  (none) — allow/deny only. The response this backs only ever
#   reveals whether the identifier is taken, never who owns it.

# admins can check whether any username or email is already taken
allow if {
    input.action == "user:exists"
    common.is_admin(input.subject)
}

# org-admins can also check whether any username or email is already taken;
# there is no resource id/org to scope against (see contract above), so this
# is unscoped like the admin rule above rather than restricted to their org
allow if {
    input.action == "user:exists"
    common.is_org_admin(input.subject)
}
