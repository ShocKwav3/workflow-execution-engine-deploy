package main

import rego.v1

role(actions, after) := {"resource_changes": [{
	"address": "aws_iam_role.example",
	"type": "aws_iam_role",
	"change": {"actions": actions, "after": after},
}]}

test_role_without_boundary_is_denied if {
	count(deny) == 1 with input as role(["create"], {"name": "example"})
}

test_role_with_boundary_is_allowed if {
	count(deny) == 0 with input as role(["create"], {"permissions_boundary": "arn:aws:iam::aws:policy/PowerUserAccess"})
}

test_replaced_role_without_boundary_is_denied if {
	count(deny) == 1 with input as role(["delete", "create"], {"name": "example"})
}

test_deleted_role_is_ignored if {
	count(deny) == 0 with input as role(["delete"], null)
}
