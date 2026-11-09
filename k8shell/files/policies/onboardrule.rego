package onboardrule

import rego.v1
import data.common

default allow := false

# admins can perform any onboardrule action, in any org
allow if {
    input.action in {"onboardrule:list", "onboardrule:create", "onboardrule:update", "onboardrule:delete"}
    common.is_admin(input.subject)
}

# org-admins can perform any onboardrule action within their own organization;
# onboardrule:update also gates ApproveOnboardRequest/RejectOnboardRequest
allow if {
    input.action in {"onboardrule:list", "onboardrule:create", "onboardrule:update", "onboardrule:delete"}
    common.is_org_admin(input.subject)
    input.resource.attributes.org == input.subject.org
}
