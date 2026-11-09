package git_test

import rego.v1

# a request bound to workspace, owned by owner ("" workspace = unbound, no owner)
git_req(action, username, roles, workspace, owner) := {
    "action": action,
    "subject": {"username": username, "roles": roles, "org": "default"},
    "resource": {"type": "repo", "id": "github.com/acme/app", "attributes": {"host": "github.com"}},
    "context": {"workspace": workspace, "workspace_owner": owner},
} if workspace != ""

git_req(action, username, roles, "", _) := {
    "action": action,
    "subject": {"username": username, "roles": roles, "org": "default"},
    "resource": {"type": "repo", "id": "github.com/acme/app", "attributes": {"host": "github.com"}},
    "context": {"workspace": ""},
}

# a request from the subject's own workspace
git_input(action, username, roles, workspace) := git_req(action, username, roles, workspace, username)

git_allowed(inp) if {
    data.git.allow with input as inp
    not data.git.deny with input as inp
}

test_user_fetches_from_own_workspace if git_allowed(git_input("git:fetch", "alice", [], "alice-ws"))

test_user_pushes_from_own_workspace if git_allowed(git_input("git:push", "alice", [], "alice-ws"))

test_unbound_request_denied if {
    not git_allowed(git_input("git:fetch", "alice", [], ""))
    not git_allowed(git_input("git:push", "alice", [], ""))
}

test_missing_workspace_denied if {
    inp := object.remove(git_input("git:push", "alice", [], "x"), ["context"])
    not git_allowed(inp)
}

test_other_users_workspace_denied if {
    not git_allowed(git_req("git:fetch", "alice", [], "carol-ws", "carol"))
    not git_allowed(git_req("git:push", "alice", [], "carol-ws", "carol"))
}

test_admin_from_other_users_workspace_denied if {
    not git_allowed(git_req("git:fetch", "root", ["admin"], "alice-ws", "alice"))
    not git_allowed(git_req("git:push", "root", ["admin"], "alice-ws", "alice"))
}

test_org_admin_from_managed_users_workspace_denied if not git_allowed(git_req("git:push", "orga", ["org-admin", "developer-admin"], "alice-ws", "alice"))

test_workspace_without_owner_denied if {
    inp := object.remove(git_input("git:fetch", "alice", [], "alice-ws"), ["context"])
    not git_allowed(object.union(inp, {"context": {"workspace": "alice-ws"}}))
}

test_empty_username_denied if not git_allowed(git_req("git:fetch", "", [], "ws", ""))

test_admin_from_own_workspace_allowed if git_allowed(git_input("git:push", "root", ["admin"], "root-ws"))

test_admin_without_own_workspace_denied if {
    not git_allowed(git_input("git:fetch", "root", ["admin"], ""))
    not git_allowed(git_input("git:push", "root", ["admin"], ""))
}

test_group_admin_without_own_workspace_denied if not git_allowed(git_input("git:push", "bob", ["developer-admin", "org-admin"], ""))

test_wrong_resource_type_denied if {
    inp := object.union(git_input("git:fetch", "alice", [], "alice-ws"), {"resource": {"type": "workspace", "id": "alice-ws"}})
    not git_allowed(inp)
}

test_empty_repo_id_denied if {
    inp := object.union(git_input("git:fetch", "alice", [], "alice-ws"), {"resource": {"id": ""}})
    not git_allowed(inp)
}

test_other_action_denied if not git_allowed(git_input("git:delete", "alice", [], "alice-ws"))

test_no_obligations if {
    inp := git_input("git:push", "alice", [], "alice-ws")
    not data.git.obligations with input as inp
}
