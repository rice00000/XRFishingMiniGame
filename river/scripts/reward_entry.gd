class_name RewardEntry
extends Resource
## "Catching X gives N of item Y". Leave object_id and pool_id empty to match any catch.

@export var object_id: StringName
@export var pool_id: StringName
@export var item_id: StringName = &"shell"
@export var quantity := 1
## Off = also granted when the caught object was a wrong answer.
@export var only_when_correct := true


func matches(obj: RiverObject, correct: bool) -> bool:
	if only_when_correct and not correct:
		return false
	if object_id != &"" and object_id != obj.config.get_id():
		return false
	if pool_id != &"" and pool_id != obj.pool_id:
		return false
	return true
