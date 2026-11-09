package session

import rego.v1
import data.common

default allow := false

# admins can perform any session action
allow if common.is_admin(input.subject)

# session:list is defined in session_list.rego

# --- session:record ---

# session:record decides what to record for a session; it is not an access
# check. The ssh:* (ssh.rego) and workspace:connect (workspace_access.rego)
# entry rules are the only gate on whether a session may happen, and callers
# consume only the obligations, never allowed — so any well-formed request
# is allowed here.
allow if input.action == "session:record"

# a malformed session:record request is rejected, regardless of admin status
deny if {
    input.action == "session:record"
    not valid_record_input
}

valid_record_input if {
    input.resource.type == "workspace"
    input.resource.id != ""
    input.resource.attributes.owner != ""
    input.context.session_type in object.keys(record_channels)
    input.context.session_source in {"ssh-proxy", "api-server"}
}

# the record obligation's comma-separated tokens for each session_type; recording
# a port-forward (direct-tcpip) also records the VS Code terminals it carries and
# their keystrokes
record_channels := {
    "shell": "shell",
    "tcpip": "direct-tcpip,vscode-terminals,vscode-input",
    "exec": "exec",
    "sftp": "sftp",
}

# --- session:record obligations ---

# record the session when the subject holds the matching record-<session_type>
# role (record-shell, record-tcpip, record-exec, record-sftp) or the session
# matches a record_rules entry; the obligation value lists the tokens to record
obligations["record"] := record_channels[input.context.session_type] if {
    input.action == "session:record"
    records_session_type
}

# explicitly disable recording for everyone else, rather than leaving it to
# the enforcer's default
obligations["record"] := "none" if {
    input.action == "session:record"
    not records_session_type
}

records_session_type if {
    sprintf("record-%s", [input.context.session_type]) in input.subject.roles
}

records_session_type if {
    some rule in record_rules
    rule.org == input.subject.org
    rule.blueprint == input.resource.attributes.blueprint
    input.context.session_type in rule.session_types
}

# sessions recorded regardless of roles: by subjects of org on workspaces built
# from blueprint, for the listed session_types
record_rules := [
    {"org": "tul-fm", "blueprint": "ct1-content", "session_types": {"shell", "tcpip", "exec"}},
]
