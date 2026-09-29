class_name RiverSpawner
extends Node3D
## Spawns SpawnPools into the river. The river flows along local +X and the
## player's shore is on the local +Z side. Objects leaving one end re-enter at the other.

@export var river_length := 10.0
@export var river_width := 3.0
## Rows at different distances from the shore.
@export_range(1, 8) var lanes := 3
@export var show_water := true
@export var water_color := Color(0.02, 0.06, 0.18)

var objects: Array[RiverObject] = []
## Optional look for spawned objects. Set by RiverGame.
var skin: RiverSkin

var _water: MeshInstance3D


func _ready() -> void:
	if not show_water:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(river_length, river_width)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = water_color
	plane.material = mat
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = plane
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)


## The plain water plane; hidden when a skin brings its own water.
func set_water_visible(value: bool) -> void:
	if _water:
		_water.visible = value


## Spawns every pool using `rng` (same seed = same objects and layout).
func spawn(pools: Array[SpawnPool], rng: RandomNumberGenerator) -> Array[RiverObject]:
	clear()
	var picks: Array = [] # [config, pool_id]
	for pool in pools:
		if pool == null:
			continue
		for cfg in pool.pick(rng):
			picks.append([cfg, pool.get_id()])
	SpawnPool.shuffle(picks, rng)

	# Spread objects over a lanes x columns grid, staggering lanes so columns don't line up.
	var columns := maxi(ceili(picks.size() / float(lanes)), 1)
	var spacing := river_length / columns
	for i in picks.size():
		var lane := i % lanes
		var column := floori(float(i) / lanes)
		var obj := RiverObject.new()
		obj.setup(picks[i][0], picks[i][1], i, river_length * 0.5, skin.scene_for(picks[i][0]) if skin else null)
		var x := -river_length * 0.5 + spacing * (column + 0.5) + spacing * lane / lanes
		obj.position = Vector3(
			wrapf(x, -river_length * 0.5, river_length * 0.5),
			obj.config.float_height,
			-river_width * 0.5 + river_width * (lane + 0.5) / lanes)
		obj.start_position = obj.position
		add_child(obj)
		objects.append(obj)
	return objects


func clear() -> void:
	for obj in objects:
		if is_instance_valid(obj):
			# Detach now so a same-frame respawn doesn't clash with the old node names.
			remove_child(obj)
			obj.queue_free()
	objects.clear()
