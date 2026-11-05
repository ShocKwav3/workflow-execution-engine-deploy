package main

import rego.v1

# The apply role may create a role only with the boundary, so a role without one fails at apply.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_iam_role"
	rc.change.after != null
	not rc.change.after.permissions_boundary
	msg := sprintf("%s has no permissions_boundary", [rc.address])
}
