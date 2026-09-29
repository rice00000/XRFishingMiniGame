class_name TagRule
extends TaskRule
## Example custom rule: every object whose config has `tag` is correct
## ("catch a red one"). Copy this file as a starting point for new rules.

@export var tag := ""


func find_targets(objects: Array[RiverObject], _task: RiverTask) -> Array[RiverObject]:
	var result: Array[RiverObject] = []
	for obj in objects:
		if obj.config.tags.has(tag):
			result.append(obj)
	return result


func describe() -> String:
	return "TAG(%s)" % tag
