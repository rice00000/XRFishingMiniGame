class_name StandardRule
extends TaskRule
## The built-in rules. Speeds are compared by magnitude; ties within
## `tie_tolerance` are all correct.

enum Kind {
	FASTEST_ROTATION,
	SLOWEST_ROTATION,
	FASTEST_MOVEMENT,
	SLOWEST_MOVEMENT,
	SAME_AS_REFERENCE,
	FROM_POOL,
}

@export var kind := Kind.FASTEST_ROTATION
## SAME_AS_REFERENCE: the config to match (by id). Empty = the task's reference_object.
@export var reference_object: RiverObjectConfig
## FROM_POOL: id of the pool whose objects are correct.
@export var pool_id: StringName
@export var tie_tolerance := 0.001


func find_targets(objects: Array[RiverObject], task: RiverTask) -> Array[RiverObject]:
	match kind:
		Kind.FASTEST_ROTATION:
			return _extreme(objects, func(o: RiverObject) -> float: return absf(o.config.rotation_speed), true)
		Kind.SLOWEST_ROTATION:
			return _extreme(objects, func(o: RiverObject) -> float: return absf(o.config.rotation_speed), false)
		Kind.FASTEST_MOVEMENT:
			return _extreme(objects, func(o: RiverObject) -> float: return absf(o.config.movement_speed), true)
		Kind.SLOWEST_MOVEMENT:
			return _extreme(objects, func(o: RiverObject) -> float: return absf(o.config.movement_speed), false)
		Kind.SAME_AS_REFERENCE:
			var ref := _reference(task)
			if ref == null:
				push_warning("StandardRule|WARN: SAME_AS_REFERENCE has no reference object")
				return []
			return _where(objects, func(o: RiverObject) -> bool: return o.config.get_id() == ref.get_id())
		Kind.FROM_POOL:
			return _where(objects, func(o: RiverObject) -> bool: return o.pool_id == pool_id)
	return []


func describe() -> String:
	var label: String = Kind.keys()[kind]
	if kind == Kind.SAME_AS_REFERENCE:
		label += "(%s)" % (String(reference_object.get_id()) if reference_object else "task reference")
	elif kind == Kind.FROM_POOL:
		label += "(%s)" % pool_id
	return label


func _reference(task: RiverTask) -> RiverObjectConfig:
	if reference_object:
		return reference_object
	return task.reference_object if task else null


func _extreme(objects: Array[RiverObject], metric: Callable, highest: bool) -> Array[RiverObject]:
	var result: Array[RiverObject] = []
	if objects.is_empty():
		return result
	var best: float = metric.call(objects[0])
	for obj in objects:
		var value: float = metric.call(obj)
		best = maxf(best, value) if highest else minf(best, value)
	for obj in objects:
		if absf(metric.call(obj) - best) <= tie_tolerance:
			result.append(obj)
	return result


func _where(objects: Array[RiverObject], predicate: Callable) -> Array[RiverObject]:
	var result: Array[RiverObject] = []
	for obj in objects:
		if predicate.call(obj):
			result.append(obj)
	return result
