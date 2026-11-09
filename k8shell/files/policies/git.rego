package git

import rego.v1

# git:fetch and git:push cover git's smart-HTTP protocol through api-server's
# git proxy (fetch: clone/fetch/pull; push: receive-pack, checked already on
# the info/refs advertisement). The resource is the upstream repo
# (type "repo", id like "github.com/acme/app", attributes.host).

default allow := false

git_actions := {"git:fetch", "git:push"}

allow if {
    input.action in git_actions
    input.resource.type == "repo"
    input.resource.id != ""
    input.subject.username != ""
    input.context.workspace != ""
    input.context.workspace_owner == input.subject.username
}
