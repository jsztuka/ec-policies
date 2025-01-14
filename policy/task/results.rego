#
# METADATA
# title: Tekton Task result
# description: Verify Tekton Task definitions provide expected results.
#
package policy.task.results

import rego.v1

import data.lib

# METADATA
# title: Required result defined
# description: >-
#   Verify if Task defines the required result. This is controlled by the `required_task_results`
#   rule data key. By default this is empty making this rule a no-op.
# custom:
#   short_name: required
#   failure_msg: '%s'
#
deny contains result if {
	some err in errors
	result := lib.result_helper(rego.metadata.chain(), [err])
}

# METADATA
# title: Rule data provided
# description: >-
#   Confirm the expected `required_task_results` rule data key has been provided in the expected
#   format.
# custom:
#   short_name: rule_data_provided
#   failure_msg: '%s'
#   solution: If provided, ensure the rule data is in the expected format.
#   collections:
#   - redhat
#   - policy_data
#
deny contains result if {
	some error in _rule_data_errors
	result := lib.result_helper(rego.metadata.chain(), [error])
}

errors contains err if {
	version := object.get(input.metadata, ["labels", "app.kubernetes.io/version"], "")
	version_constraints := {v | some r in lib.rule_data(_rule_data_key); v := r.version}
	not version in version_constraints

	some required in {r |
		some r in lib.rule_data(_rule_data_key)
		input.metadata.name == r.task
		not r.version
	}
	found := [result |
		some result in input.spec.results
		result.name == required.result
	]
	count(found) == 0
	err := sprintf("%q result not found in %q Task%s (all versions)", [required.result, required.task, _vstr(version)])
}

errors contains err if {
	version := object.get(input.metadata, ["labels", "app.kubernetes.io/version"], "")
	some required in {r |
		some r in lib.rule_data(_rule_data_key)
		input.metadata.name == r.task
		r.version == version
	}
	found := [result |
		some result in input.spec.results
		result.name == required.result
	]
	count(found) == 0
	err := sprintf("%q result not found in %q Task/v%s", [required.result, required.task, version])
}

_rule_data_errors contains err if {
	schema := {
		"$schema": "http://json-schema.org/draft-07/schema#",
		"type": "array",
		"items": {
			"type": "object",
			"properties": {
				"task": {"type": "string"},
				"version": {"type": "string"},
				"result": {"type": "string"},
			},
			"additionalProperties": false,
			"required": ["task", "result"],
		},
		"uniqueItems": true,
	}

	# match_schema expects either a marshaled JSON resource (String) or an Object. It doesn't
	# handle an Array directly.
	value := json.marshal(lib.rule_data(_rule_data_key))
	some violation in json.match_schema(value, schema)[1]
	err := sprintf("Rule data %s has unexpected format: %s", [_rule_data_key, violation.error])
}

_rule_data_key := "required_task_results"

_vstr(v) := s if {
	v != ""
	s := sprintf("/v%s", [v])
} else := ""
