package audit

import rego.v1
import data.common

default allow := false

# admins can list all audit records, unscoped
allow if {
    input.action == "audit:list"
    common.is_admin(input.subject)
}

# org-admins can list audit records, scoped to their own org via the "org"
# obligation below
allow if {
    input.action == "audit:list"
    common.is_org_admin(input.subject)
}

# --- audit:list obligations ---

# an org-admin's listing is scoped to the single org they're a member of;
# full admins are exempt since they can see every org
obligations["org"] := input.subject.org if {
    input.action == "audit:list"
    common.is_org_admin(input.subject)
    not common.is_admin(input.subject)
}
