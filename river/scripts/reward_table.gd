class_name RewardTable
extends Resource
## Every matching entry is granted, so entries stack (a generic reward plus a bonus).

@export var entries: Array[RewardEntry] = []


## item_id -> quantity for catching `obj`.
func rewards_for(obj: RiverObject, correct: bool) -> Dictionary:
	var result := {}
	for entry in entries:
		if entry != null and entry.matches(obj, correct):
			result[entry.item_id] = result.get(entry.item_id, 0) + entry.quantity
	return result
