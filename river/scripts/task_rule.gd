class_name TaskRule
extends Resource
## Answer logic for a task. To add a custom rule: make a script that
## `extends TaskRule`, override find_targets() (and describe() for nicer logs),
## then pick it in a RiverTask's `rule` slot. See TagRule for a small example.


## Returns every spawned object that counts as a correct answer.
## Several are allowed (ties, "any red one"). Empty = nothing is correct.
func find_targets(_objects: Array[RiverObject], _task: RiverTask) -> Array[RiverObject]:
	return []


## Short label written to the trial log.
func describe() -> String:
	var script: Script = get_script()
	return script.get_global_name() if script else "TaskRule"
