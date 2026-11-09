package threat

import rego.v1
import data.common

# threat:list grants querying the threats worktrace detected. Admins list
# every threat (the admin rule in threat_detect.rego); org-admins list the
# threats of the organization they manage, scoped via the "org" obligation
# below. Nobody else gets it.

allow if {
    input.action == "threat:list"
    common.is_org_admin(input.subject)
}

# --- threat:list obligations ---

# an org-admin's listing is scoped to the single org they're a member of;
# full admins are exempt since they can see every org
obligations["org"] := input.subject.org if {
    input.action == "threat:list"
    common.is_org_admin(input.subject)
    not common.is_admin(input.subject)
}
