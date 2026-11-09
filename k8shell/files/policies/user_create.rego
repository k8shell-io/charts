package user

import rego.v1
import data.common

# admins can create any user account
allow if {
    input.action == "user:create"
    common.is_admin(input.subject)
}

# an org-admin can create user accounts within their own organization
allow if {
    input.action == "user:create"
    common.is_org_admin(input.subject)
    input.resource.attributes.org == input.subject.org
}
