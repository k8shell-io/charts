package workspace

import rego.v1
import data.common

default allow := false

# admins may perform any workspace action
allow if common.is_admin(input.subject)

# workspace actions scoped to a single resource's owner; workspace:list is
# handled separately in workspace_list.rego since it has no single owner
owner_scoped_actions := {"workspace:provision", "workspace:create",
    "workspace:read", "workspace:delete", "workspace:connect",
    "workspace:files", "workspace:app"}

# users may perform any owner-scoped workspace action on resources they own
allow if {
    input.action in owner_scoped_actions
    input.resource.attributes.owner == input.subject.username
}

# a <group>-admin can perform any owner-scoped workspace action on resources
# owned by their managed <group>-user accounts
allow if {
    input.action in owner_scoped_actions
    common.managed_by_group_admin(input.subject, enrich.user(input.resource.attributes.owner))
}

# --- workspace:update ---

# cpu, memory, network, proxy, and schedule are the mutable
# runtime-configuration slices a workspace can be updated on;
# workspace:update is evaluated once per data_type (see the contract comment
# at the top of this file), so this set gates each evaluation independently
update_data_types := {"cpu", "memory", "network", "proxy", "schedule"}

# owner_update_data_types is the subset of update_data_types a plain owner
# may update on their own workspace. "proxy" (network.webProxy, which in
# turn authorizes the {port}--{workspace} port-forward proxy) is the owner's
# to open up or lock down; cpu/memory/network stay admin/org-admin only.
# "schedule" (overriding a running workspace's expiry "to" and grace
# periods, or reverting to the blueprint's schedule) also stays
# admin/org-admin only: the provisioner does not authorize it and there is no
# obligation capping how far "to" may move, so letting owners do it would let
# them extend their own workspace indefinitely.
owner_update_data_types := {"proxy"}

# owners may update the owner-updatable slices of their own workspace; unlike
# owner_scoped_actions this is not extended to <group>-admins — only full
# site admins (blanket rule above) and org-admins (rule below) may do it on
# someone else's workspace
allow if {
    input.action == "workspace:update"
    input.context.data_type in owner_update_data_types
    input.resource.attributes.owner == input.subject.username
}

# an org-admin can update any of the mutable slices for a workspace owned by
# a user in their own organization; full site admins already cover every
# workspace via the blanket admin rule above. This is intentionally narrower
# than owner_scoped_actions' common.managed_by_group_admin: a plain
# <group>-admin (e.g. "developer-admin") does not get this permission, only
# an org-admin does — and a full site admin's own workspace stays off limits
# to an org-admin, same as common.protected_admin elsewhere
allow if {
    input.action == "workspace:update"
    input.context.data_type in update_data_types
    common.is_org_admin(input.subject)
    owner := enrich.user(input.resource.attributes.owner)
    input.subject.org == owner.organization
    not common.protected_admin(owner)
}

# --- workspace:start:force ---

# workspace:start:force never gates the start itself (the route's own authz
# does); api-server evaluates it on every start and sets force on the
# provisioner's StartWorkspace only when allowed, letting the caller start a
# workspace stopped by schedule expiry. The provisioner does not authorize
# force, so this is the only gate. Plain owners are deliberately left out —
# force-starting past expiry is the same kind of override as
# workspace:update data_type=schedule, which is admin-only too. Full site
# admins are covered by the blanket admin rule above.

# a <group>-admin or org-admin may force-start workspaces owned by accounts
# they manage (see common.managed_by_group_admin: managed <group>-users, peer
# <group>-admins, and for an org-admin everyone in their org); a full site
# admin's workspace stays off limits via common.protected_admin
allow if {
    input.action == "workspace:start:force"
    common.managed_by_group_admin(input.subject, enrich.user(input.resource.attributes.owner))
}

# a <group>-admin or org-admin may also force-start their own workspace
# ("org-admin" ends in "-admin", so common.group_admin_roles covers it)
allow if {
    input.action == "workspace:start:force"
    input.resource.attributes.owner == input.subject.username
    count(common.group_admin_roles(input.subject.roles)) > 0
}

# inject-mode provisioning is restricted to users holding common.inject_role
# — attaching a workspace to an existing workload requires it regardless of
# ownership or admin status
deny if {
    input.action == "workspace:provision"
    input.context.mode == "inject"
    not common.inject_role in input.subject.roles
}

# inject-mode workspace:create is evaluated against the target owner's
# roles, not the acting subject's — this lets a <group>-admin create an
# inject-mode workspace on behalf of a managed user based on that user's own
# standing, rather than the admin's; standalone workspace:create is
# unaffected and continues to be governed solely by the owner-scoped rules
# above
deny if {
    input.action == "workspace:create"
    input.context.mode == "inject"
    owner := enrich.user(input.resource.attributes.owner)
    not common.inject_role in owner.roles
}

# --- git-source provisioning/creation ---

# git-source provisioning is restricted to users holding the "git-workspace"
# role — same role common.onboarded_via_git_idp gates repo-catalog access
# behind, since a context.source == "git" request supplies an ad hoc
# blueprint from that same repo catalog. Applies regardless of ownership or
# admin status, same as the inject-mode checks above.
deny if {
    input.action == "workspace:provision"
    input.context.source == "git"
    not common.git_workspace_role in input.subject.roles
}

# workspace:create's source check is evaluated against the target owner, not
# the acting subject — same as the inject-mode workspace:create checks
# above, since the resulting workspace (and its git access) belongs to that
# owner, not necessarily to a <group>-admin creating on their behalf
deny if {
    input.action == "workspace:create"
    input.context.source == "git"
    owner := enrich.user(input.resource.attributes.owner)
    not common.git_workspace_role in owner.roles
}

# --- catalog-source provisioning ---

# standalone catalog-source provisioning is restricted to blueprints the
# owner is actually assigned (enrich.user(...).blueprints) — inject mode is
# exempt because there the blueprint name is derived from the target repo,
# not picked from the catalog, and can never appear in a user's assigned
# blueprint list. A "*" entry (assigned to e.g. admins, see
# usermap-template.yaml) means the owner is assigned every blueprint.
deny if {
    input.action == "workspace:provision"
    input.context.mode == "standalone"
    input.context.source == "catalog"
    parsed_blueprint := yaml.unmarshal(input.context.blueprint)
    owner := enrich.user(input.resource.attributes.owner)
    not parsed_blueprint.metadata.name in owner.blueprints
    not "*" in owner.blueprints
}

# --- workspace:provision obligations ---

# non-privileged for plain users; full admins and org-admins are exempt
obligations["patch:/securityContext/privileged"] := false if {
    input.action == "workspace:provision"
    not common.is_admin(input.subject)
    not common.is_org_admin(input.subject)
}