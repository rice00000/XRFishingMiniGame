class_name SpawnPool
extends Resource
## A group of objects and how many of them to spawn per trial. A task's own
## `objects` form one pool; add more in the task's "Advanced > extra_pools" to mix
## groups, e.g. one fixed target plus 3 random distractors.

## Used by rewards and logs. Empty = the resource file name.
@export var name: StringName
@export var objects: Array[RiverObjectConfig] = []
## How many to spawn per trial. 0 = all of them.
@export_range(0, 50) var count := 0
## Pick each object at most once. Off = duplicates are possible.
@export var unique := true

var _expanded: Array[RiverObjectConfig] = []


func get_id() -> StringName:
	if name != &"":
		return name
	return StringName(resource_path.get_file().get_basename())


## Every object this pool can spawn, with `variable` applied.
func get_objects() -> Array[RiverObjectConfig]:
	if _expanded.is_empty():
		for cfg in objects:
			if cfg:
				_expanded.append_array(cfg.expand())
	return _expanded


func pick(rng: RandomNumberGenerator) -> Array[RiverObjectConfig]:
	var result: Array[RiverObjectConfig] = []
	var valid := get_objects().duplicate()
	if valid.is_empty():
		return result
	var wanted := count if count > 0 else valid.size()

	if unique:
		if wanted > valid.size():
			push_warning("SpawnPool|WARN: '%s' wants %d unique objects but has %d" % [get_id(), wanted, valid.size()])
		shuffle(valid, rng)
		for i in mini(wanted, valid.size()):
			result.append(valid[i])
	else:
		for i in wanted:
			result.append(valid[rng.randi_range(0, valid.size() - 1)])
	return result


## Seeded Fisher-Yates. Array.shuffle() uses the global RNG, which would break replaying a seed.
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
