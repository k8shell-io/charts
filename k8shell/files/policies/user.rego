package user

import rego.v1
import data.common

default allow := false

# admins can perform any user action except those explicitly denied
admin_denied_actions := {"token:create"}

allow if {
    common.is_admin(input.subject)
    not input.action in admin_denied_actions
}

# users can create tokens for themselves
allow if {
    input.action == "token:create"
    input.subject.username == input.resource.id
}

# --- token:create obligations ---

obligations["expires_in"] := "24h" if {
    input.action == "token:create"
    input.context.source == "web-flow"
}
