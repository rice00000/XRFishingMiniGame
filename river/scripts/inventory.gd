class_name Inventory
extends Node
## item_id -> quantity. Filled from the RewardTable when objects are caught.

signal changed(item_id: StringName, total: int)

var items: Dictionary[StringName, int] = {}


func add(item_id: StringName, quantity: int = 1) -> void:
	items[item_id] = items.get(item_id, 0) + quantity
	changed.emit(item_id, items[item_id])


func count(item_id: StringName) -> int:
	return items.get(item_id, 0)


func clear() -> void:
	items.clear()
