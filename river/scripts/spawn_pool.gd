class_name SpawnPool
extends Resource
## A bag of object configs and how many to spawn from it per trial.

## Used by FROM_POOL rules, rewards and logs. Empty = the resource file name.
@export var id: StringName
@export var objects: Array[RiverObjectConfig] = []
@export_range(0, 50) var count := 1
## Pick each config at most once (count is capped at objects.size()).
## Off = pick with replacement, so duplicates are possible.
@export var unique := true


func get_id() -> StringName:
	if id != &"":
		return id
	return StringName(resource_path.get_file().get_basename())


func pick(rng: RandomNumberGenerator) -> Array[RiverObjectConfig]:
	var result: Array[RiverObjectConfig] = []
	var valid: Array[RiverObjectConfig] = []
	for cfg in objects:
		if cfg != null:
			valid.append(cfg)
	if valid.is_empty():
		return result

	if unique:
		if count > valid.size():
			push_warning("SpawnPool|WARN: '%s' wants %d unique objects but has %d" % [get_id(), count, valid.size()])
		shuffle(valid, rng)
		for i in mini(count, valid.size()):
			result.append(valid[i])
	else:
		for i in count:
			result.append(valid[rng.randi_range(0, valid.size() - 1)])
	return result


## Seeded Fisher-Yates. Array.shuffle() uses the global RNG, which would break replaying a seed.
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
