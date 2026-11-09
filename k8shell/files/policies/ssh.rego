package ssh

import rego.v1
import data.common

default allow := false

allow if {
    input.resource.type == "workspace"
    common.is_admin(input.subject)
}

_ssh_user_actions := {"ssh:shell", "ssh:exec", "ssh:sftp",
    "ssh:direct-tcpip", "ssh:direct-streamlocal", "ssh:agent-forward"}

allow if {
    input.action in _ssh_user_actions
    input.resource.type == "workspace"
    input.resource.attributes.owner == input.subject.username
}

deny if {
    input.action in {"ssh:shell", "ssh:exec"}
    input.context.as_user == "root"
    not input.subject.sudo == true
}