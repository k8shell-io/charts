package license

import rego.v1
import data.common

default allow := false

# --- license:write ---
#
# Uploading (including a dry run that only previews it) and removing the
# installation's license. A license changes what the whole installation may
# hold, so only admins. Reading the license status needs no action of its
# own: GET /license is open to every authenticated user, its usage narrowed
# by org:list.

allow if {
    input.action == "license:write"
    common.is_admin(input.subject)
}
