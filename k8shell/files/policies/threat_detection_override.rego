package threat

import rego.v1
import data.common

# threat:detection:override covers reading, setting and clearing a
# workspace's detection override, which replaces the threat:detect obligation
# for the workspace until it is cleared. Since an override can switch
# detection off, it is granted narrowly: admins on every workspace (the admin
# rule in threat_detect.rego), org-admins on workspaces of users in their
# organization and on their own workspaces, <group>-admins on workspaces of
# users they manage. Nobody else gets it, not even the workspace owner.

# an org-admin or <group>-admin may override the detection of a workspace
# owned by an account they manage (org-admin: same org; <group>-admin: same
# org and group, or a peer <group>-admin); with no resource id this answers
# the capability probe for that owner. Their own workspaces are excluded
# here; an org-admin gets theirs through the rule below.
allow if {
    input.action == "threat:detection:override"
    input.resource.type == "workspace"
    owner := input.resource.attributes.owner
    owner != ""
    owner != input.subject.username
    common.managed_by_group_admin(input.subject, enrich.user(owner))
}

# an org-admin may also override the detection of their own workspace; a
# <group>-admin still may not. With no resource id this answers the
# capability probe.
allow if {
    input.action == "threat:detection:override"
    input.resource.type == "workspace"
    common.is_org_admin(input.subject)
    input.resource.attributes.owner == input.subject.username
}
