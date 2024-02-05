package lib.refs

import rego.v1

# Return an object that represents the task "name", "kind", and "bundle". "bundle" is
# omitted if a bundle is not used.
#
# As task reference can take different shapes depending on which resolver is being used.
# When a bundle reference is used, there are two mechanisms. The old-style which uses
# the .bundle attribute, and the new-style via the Bundle Resolver. It is technically
# possible to create a task reference that contains both styles. In such cases, Tekton
# gives precedence to the old-style. Further, Tekton falls back to the local resolver if
# a bundle is not used in neither format. The "else" usage in this function ensures the
# same precendence order is honored.
# regal ignore:rule-length
task_ref(task) := i if {
	# Handle old-style bundle reference
	r := _ref(task)
	bundle := r.bundle
	i := {
		"bundle": bundle,
		"name": _ref_name(task),
		"kind": lower(object.get(r, "kind", "task")),
		"pinned": _has_digest(bundle),
	}
} else := i if {
	# Handle bundle-resolver reference
	r := _ref(task)
	r.resolver == "bundles"
	bundle := _param(r, "bundle", "")
	i := {
		"bundle": bundle,
		"name": _ref_name(task),
		"kind": lower(_param(r, "kind", "task")),
		"pinned": _has_digest(bundle),
	}
} else := i if {
	r := _ref(task)
	r.resolver == "git"
	revision := _param(r, "revision", "")
	i := {
		"url": _param(r, "url", ""),
		"revision": revision,
		"pathInRepo": _param(r, "pathInRepo", ""),
		"name": _ref_name(task),
		"kind": lower(object.get(r, "kind", "task")),
		"pinned": _is_sha1(revision),
	}
} else := i if {
	# Handle inlined Task definitions
	_ref(task) == {}
	i := {
		# The Task definition itself is inlined without a name. Use a special value here to
		# distinguish from other reference types.
		"name": _no_task_name,
		"kind": "task",
		"pinned": true,
	}
} else := i if {
	# Handle local reference
	r := _ref(task)
	i := {
		"name": _ref_name(task),
		"kind": lower(object.get(r, "kind", "task")),
		"pinned": false,
	}
}

default _is_sha1(_) := false

_is_sha1(value) if regex.match(`^[0-9a-f]{40}$`, value)

default _has_digest(_) := false

_has_digest(value) if contains(value, "@sha256:")

_param(taskRef, name, fallback) := value if {
	some param in taskRef.params
	param.name == name
	value := param.value
} else := fallback

_ref(task) := r if {
	# Reference from within a PipelineRun slsa v0.2 attestation
	r := task.ref
} else := r if {
	# Reference from within a Pipeline definition or a PipelineRun slsa v1.0 attestation
	r := task.taskRef
} else := r if {
	# reference from a taskRun in a slsav1 attestation
	r := task.spec.taskRef
} else := {}

# _ref_name returns the name of the given Task. This is the name taken from the Task definition. It
# tries to grab the name from the "tekton.dev/task" which is automatically added by the Tekton
# Pipeline controller: https://tekton.dev/docs/pipelines/labels/#automatic-labeling
# There are a few reasons the label may not be available. The first is due to incomplete data,
# usually in the unit tests. The second is if this is processing a Pipeline/Task definition
# directly. Finally, the last is if the Task is an inlined/embedded Task.
_ref_name(task) := name if {
	# Location of labels in SLSA Provenance v1.0
	some label, value in task.metadata.labels
	label == "tekton.dev/task"
	name := value
} else := name if {
	# Location of labels in SLSA Provenance v0.2
	some label, value in task.invocation.environment.labels
	label == "tekton.dev/task"
	name := value
} else := name if {
	# Some resolvers specify the name of the Task as a parameter, e.g. bundles and hub.
	name := _param(_ref(task), "name", "")
	name != ""
} else := name if {
	# Pipeline/Task definition
	name := _ref(task).name
} else := _no_task_name

_no_task_name := "<NAMELESS>"
