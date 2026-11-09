package announcement

import rego.v1
import data.common

default allow := false

# admins can create, update, or delete any announcement, regardless of its
# orgs scope (including global, where orgs is empty)
allow if {
    input.action == "announcement:write"
    common.is_admin(input.subject)
}

# org-admins can create, update, or delete announcements that apply to their
# own org — membership, not equality, so an announcement scoped to their org
# alongside others is still theirs to touch as long as their org is one of
# the targets. An empty/global orgs has no members, so it's naturally
# excluded. See the "orgs" contract note for why this is the announcement's
# requested scope on create but its current scope on update/delete.
allow if {
    input.action == "announcement:write"
    common.is_org_admin(input.subject)
    input.subject.org in announcement_orgs(input.resource)
}

# announcement_orgs parses the resource's comma-separated "orgs" attribute
# into a set, trimming whitespace around each entry; an absent/empty
# attribute yields the empty set (global scope)
default announcement_orgs(resource) := set()

announcement_orgs(resource) := orgs if {
    raw := object.get(resource.attributes, "orgs", "")
    raw != ""
    orgs := {trim_space(org) | some org in split(raw, ",")}
}
