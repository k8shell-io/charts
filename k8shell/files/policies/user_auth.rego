package user

import rego.v1
import data.common

# any authenticated user can authenticate via SSH or web
allow if input.action == "user:auth"

# true when the subject already authenticated upstream through an external
# IdP; such subjects must never fall back to a local password, on any surface.
# idp.k8shell.io/file is identity's own local user file (identity.users of the
# chart), not an external IdP: its users may use their password.
onboarded_via_idp if {
    startswith(input.subject.source, "idp.k8shell.io/")
    input.subject.source != "idp.k8shell.io/file"
}

# local users may use a password on the web surface
obligations["auth_methods"] := ["password"] if {
    input.action == "user:auth"
    input.context.surface == "web"
    not onboarded_via_idp
}

# IdP-onboarded subjects (github/gitlab/oidc/...) are SSO-only on the web
# surface — no password fallback
obligations["auth_methods"] := ["sso"] if {
    input.action == "user:auth"
    input.context.surface == "web"
    onboarded_via_idp
}

obligations["auth_methods"] := ["publickey", "password"] if {
    input.action == "user:auth"
    input.context.surface == "ssh"
    not onboarded_via_idp
}

obligations["auth_methods"] := ["publickey"] if {
    input.action == "user:auth"
    input.context.surface == "ssh"
    onboarded_via_idp
}
