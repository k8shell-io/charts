package blueprint

import rego.v1
import data.common

default allow := false

# admins can read the blueprint catalog across every org
allow if {
    input.action == "blueprints:read"
    common.is_admin(input.subject)
}

# org-admins can read the catalog, scoped to their own org via the "org"
# obligation below
allow if {
    input.action == "blueprints:read"
    common.is_org_admin(input.subject)
}

# --- blueprints:read obligations ---

# full admins see every org's blueprints
obligations["org"] := "*" if {
    input.action == "blueprints:read"
    common.is_admin(input.subject)
}

# org-admins are scoped to the single org they're a member of
obligations["org"] := input.subject.org if {
    input.action == "blueprints:read"
    common.is_org_admin(input.subject)
    not common.is_admin(input.subject)
}

# admins can write blueprints
allow if {
    input.action == "blueprints:write"
    common.is_admin(input.subject)
}

# org-admins can write blueprints; the org a blueprint is scoped to is
# carried by the RPC request, not this policy input
allow if {
    input.action == "blueprints:write"
    common.is_org_admin(input.subject)
}
