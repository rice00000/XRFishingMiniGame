class_name RiverObject
extends Node3D
## A spawned object in the river, created by RiverSpawner from a RiverObjectConfig.
## Swims back and forth along the parent's local X axis and spins its visual. No physics.

var config: RiverObjectConfig
var pool_id: StringName
## Unique per trial. Tells two copies of the same config apart in the logs.
var index := -1
## Set when harpooned: stops moving and can't be selected again.
var caught := false
var start_position := Vector3.ZERO
## What was shown: a scene path or "placeholder:<SHAPE>". Logged, since visuals can come from a skin.
var visual_source := ""

var _visual: Node3D
var _base_basis := Basis.IDENTITY
var _spin_axis := Vector3.ZERO
var _angle := 0.0
var _wrap_half_length := INF
## +1 = moving the way `swim_speed_m_per_s` points, -1 = turned around at a river end.
var _direction := 1.0


func setup(p_config: RiverObjectConfig, p_pool_id: StringName, p_index: int, wrap_half_length: float, skin_scene: PackedScene = null) -> void:
	config = p_config
	pool_id = p_pool_id
	index = p_index
	_wrap_half_length = wrap_half_length
	name = "%s_%d" % [config.get_id(), index]

	_visual = build_visual(config, skin_scene)
	var scene := skin_scene if skin_scene else config.scene
	visual_source = scene.resource_path if scene else "placeholder:%s" % config.shape
	add_child(_visual)
	_base_basis = Basis.from_euler(config.start_tilt_degrees * (PI / 180.0))
	_visual.basis = _base_basis
	if config.spin_axis.length_squared() > 0.0:
		_spin_axis = config.spin_axis.normalized()


func get_pick_radius() -> float:
	return config.get_pick_radius()


func _process(delta: float) -> void:
	if caught:
		return

	if config.swim_speed_m_per_s != 0.0:
		position.x += config.swim_speed_m_per_s * _direction * delta
		# Swim back and forth: turn around at each end of the river.
		if position.x > _wrap_half_length or position.x < -_wrap_half_length:
			position.x = clampf(position.x, -_wrap_half_length, _wrap_half_length)
			_direction = -_direction
			rotation.y = 0.0 if _direction > 0.0 else PI

	if config.spin_speed_deg_per_s != 0.0 and _spin_axis != Vector3.ZERO:
		_angle = fmod(_angle + deg_to_rad(config.spin_speed_deg_per_s) * delta, TAU)
		_visual.basis = Basis(_spin_axis, _angle) * _base_basis


func to_log_dict() -> Dictionary:
	return {
		"index": index,
		"id": String(config.get_id()),
		"pool": String(pool_id),
		"config": config.resource_path,
		"variant_of": String(config.variant_of),
		"visual": visual_source,
		"tags": Array(config.tags),
		"size": config.size,
		"swim_speed_m_per_s": config.swim_speed_m_per_s,
		"spin_speed_deg_per_s": config.spin_speed_deg_per_s,
		"spin_axis": vec_to_array(config.spin_axis),
		"start_tilt_degrees": vec_to_array(config.start_tilt_degrees),
		"start_position": vec_to_array(start_position),
	}


static func vec_to_array(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## Builds the visual for a config: `skin_scene` (from a RiverSkin) if given, else the
## config's own scene, else a placeholder shape. Scenes are scaled to `size` and
## centred on the origin. Also used by TaskUI for reference previews.
static func build_visual(cfg: RiverObjectConfig, skin_scene: PackedScene = null) -> Node3D:
	var root := Node3D.new()
	var body: Node3D = null
	var scene := skin_scene if skin_scene else cfg.scene
	if scene:
		var inst := scene.instantiate()
		body = inst as Node3D
		if body == null:
			push_error("RiverObject|ERROR: scene for '%s' is not a Node3D, using placeholder" % cfg.get_id())
			inst.free()
	if body == null:
		body = _make_placeholder(cfg)
	root.add_child(body)

	# A skin scene carries its own orientation, so the config's model fixes don't apply.
	var own_model := scene != null and skin_scene == null
	var rot := Basis.from_euler(cfg.model_orientation_fix_degrees * (PI / 180.0)) if own_model else Basis.IDENTITY
	var scale_factor := 1.0
	var center := Vector3.ZERO
	if scene and (cfg.scale_model_to_size or skin_scene):
		var bounds := _visual_bounds(body, Transform3D.IDENTITY)
		if bounds.get_longest_axis_size() > 0.0:
			scale_factor = cfg.size / bounds.get_longest_axis_size()
			center = bounds.get_center()
	body.basis = rot * scale_factor
	body.position = (cfg.model_offset_fix_m if own_model else Vector3.ZERO) - body.basis * center
	return root


static func _make_placeholder(cfg: RiverObjectConfig) -> Node3D:
	var s := cfg.size
	var mesh: PrimitiveMesh
	match cfg.shape:
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(s, s * 0.6, s * 0.6)
			mesh = box
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = s * 0.3
			cylinder.bottom_radius = s * 0.3
			cylinder.height = s
			mesh = cylinder
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = s * 0.25
			capsule.height = s
			mesh = capsule
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = s * 0.45
			cone.height = s
			mesh = cone
		"torus":
			var torus := TorusMesh.new()
			torus.inner_radius = s * 0.28
			torus.outer_radius = s * 0.5
			mesh = torus
		_:
			var sphere := SphereMesh.new()
			sphere.radius = s * 0.5
			sphere.height = s
			mesh = sphere
	mesh.material = _bright_material(cfg.color)

	var shape := MeshInstance3D.new()
	shape.mesh = mesh

	if cfg.show_spin_marker:
		var marker_mesh := BoxMesh.new()
		marker_mesh.size = Vector3.ONE * s * 0.28
		var contrast := Color.BLACK if cfg.color.get_luminance() > 0.5 else Color.WHITE
		marker_mesh.material = _bright_material(contrast)
		var marker := MeshInstance3D.new()
		marker.mesh = marker_mesh
		marker.position = Vector3(s * 0.45, 0.0, 0.0)
		shape.add_child(marker)
	return shape


static func _bright_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	# A little self-illumination keeps colours saturated in dim scenes.
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	return mat


## Merged AABB of every VisualInstance3D under `node`, in `node`'s space. Works outside the tree.
static func _visual_bounds(node: Node, xform: Transform3D) -> AABB:
	var box := AABB()
	var found := false
	if node is VisualInstance3D:
		box = xform * (node as VisualInstance3D).get_aabb()
		found = true
	for child in node.get_children():
		var child_xform := xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		var child_box := _visual_bounds(child, child_xform)
		if child_box.size == Vector3.ZERO:
			continue
		box = box.merge(child_box) if found else child_box
		found = true
	return box
