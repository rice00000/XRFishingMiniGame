class_name Harpoon
extends Node3D
## Aim + one confirm input, read from an AimInput (XR controller, mouse/keyboard/
## gamepad, ...). No projectile physics, spread or recoil: on confirm the target is
## chosen immediately (see pick()), `fired` is emitted, and only then does the spear
## animation play. The animation never changes the result.

## Emitted the moment the player confirms. `target` is null on a miss.
signal fired(target: RiverObject, time_usec: int, aim_origin: Vector3, aim_direction: Vector3)
signal animation_finished

## Spear model (tip at the origin, pointing -Z). Empty = built-in simple spear.
@export var spear_scene: PackedScene:
	set(value):
		spear_scene = value
		if is_node_ready():
			_rebuild_spear()

@export_group("Reticle")
## Selection cone half-angle in degrees. An object whose outline is within this angle
## of the aim ray can be picked. Larger = more forgiving aiming.
@export_range(0.5, 20.0) var assist_angle := 4.0
@export var reticle_color := Color(1.0, 0.9, 0.0)
@export var outline_color := Color.BLACK
## Ring thickness as a fraction of its radius.
@export_range(0.05, 0.5) var reticle_thickness := 0.2
## Draw the ring around the object that would be picked.
@export var snap_to_target := true
## Draw a line from the aim origin to the reticle, if the input asks for one (XR).
@export var show_beam := true
## Where the ring floats when nothing is under it.
@export var idle_distance := 4.0

@export_group("Spear")
## Show the spear in hand, pointing at the reticle, between throws.
@export var show_held_spear := true
## How far in front of the hold point the held spear's tip sits.
@export var hold_reach := 0.8
@export var travel_time := 0.35
## Time the spear stays on the target before animation_finished.
@export var hold_time := 0.25
@export var miss_distance := 8.0

## Where aim and confirm come from. Set by RiverGame.
var input: AimInput:
	set(value):
		if input and input.confirm_pressed.is_connected(confirm):
			input.confirm_pressed.disconnect(confirm)
		input = value
		if input:
			input.confirm_pressed.connect(confirm)
## Set by RiverGame: confirms are ignored while false.
var enabled := false
## Objects that can be picked. Set by RiverGame.
var candidates: Array[RiverObject] = []
## What would be picked right now (for the reticle).
var hovered: RiverObject

var _reticle: Node3D
var _beam: MeshInstance3D
var _spear: Node3D
var _anim_time := -1.0 # < 0 = not animating
var _anim_from := Vector3.ZERO
var _anim_miss_point := Vector3.ZERO
var _anim_target: RiverObject


func _ready() -> void:
	_reticle = _make_reticle()
	_beam = _make_beam()
	for node: Node3D in [_reticle, _beam]:
		node.top_level = true
		node.visible = false
		add_child(node)
	_rebuild_spear()


## Selects immediately, emits `fired`, then plays the spear animation.
func confirm() -> void:
	if not enabled or _anim_time >= 0.0 or input == null:
		return
	var time_usec := Time.get_ticks_usec()
	var ray := input.get_aim_ray()
	if ray.is_empty():
		return
	var target := pick(ray[0], ray[1])
	fired.emit(target, time_usec, ray[0], ray[1])

	_anim_from = _spear.global_position if _spear.visible else input.get_hold_point()
	_anim_miss_point = ray[0] + ray[1] * miss_distance
	_anim_target = target
	_anim_time = 0.0
	_spear.visible = true
	input.pulse()


## The object the aim ray selects, or null. Deterministic: the smallest angle between
## the ray and an object's pick sphere, within assist_angle; ties go to the nearer centre.
func pick(origin: Vector3, direction: Vector3) -> RiverObject:
	var best: RiverObject = null
	var best_gap := INF
	var best_center := INF
	var max_gap := deg_to_rad(assist_angle)
	for obj in candidates:
		if not is_instance_valid(obj) or obj.caught or not obj.visible:
			continue
		var to_obj := obj.global_position - origin
		var distance := to_obj.length()
		if distance < 0.001:
			continue
		var center_angle := direction.angle_to(to_obj)
		var gap := maxf(center_angle - atan(obj.get_pick_radius() / distance), 0.0)
		if gap > max_gap:
			continue
		if gap < best_gap or (gap == best_gap and center_angle < best_center):
			best = obj
			best_gap = gap
			best_center = center_angle
	return best


func _process(delta: float) -> void:
	if _anim_time >= 0.0:
		_update_throw(delta)
	else:
		_update_aim()


func _update_aim() -> void:
	var ray := input.get_aim_ray() if input else []
	_spear.visible = show_held_spear and not ray.is_empty()
	if ray.is_empty() or not enabled:
		hovered = null
		_reticle.visible = false
		_beam.visible = false
		if _spear.visible:
			_hold_spear_towards(ray[0] + ray[1] * idle_distance)
		return

	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	hovered = pick(origin, direction)

	var center := origin + direction * idle_distance
	var radius := idle_distance * tan(deg_to_rad(assist_angle))
	if hovered and snap_to_target:
		center = hovered.global_position
		radius = hovered.get_pick_radius() * 1.3

	var view_camera := get_viewport().get_camera_3d()
	var eye := view_camera.global_position if view_camera else origin
	# Torus lies in its XZ plane; turn it so the viewer looks through the ring.
	var ring_basis := _basis_towards(center - eye) * Basis(Vector3.RIGHT, PI / 2.0)
	_reticle.global_transform = Transform3D(ring_basis * radius, center)
	_reticle.visible = true

	var beam_vector := center - origin
	_beam.visible = show_beam and input.wants_beam() and beam_vector.length() > 0.01
	if _beam.visible:
		var beam_basis := _basis_towards(beam_vector).scaled_local(Vector3(1.0, 1.0, beam_vector.length()))
		_beam.global_transform = Transform3D(beam_basis, origin + beam_vector * 0.5)

	if _spear.visible:
		_hold_spear_towards(center)


func _hold_spear_towards(point: Vector3) -> void:
	var hold := input.get_hold_point()
	var direction := point - hold
	if direction.length_squared() > 0.0001:
		var b := _basis_towards(direction)
		_spear.global_transform = Transform3D(b, hold - b.z * hold_reach)


func _update_throw(delta: float) -> void:
	_anim_time += delta
	var to := _anim_target.global_position if is_instance_valid(_anim_target) else _anim_miss_point
	var k := clampf(_anim_time / maxf(travel_time, 0.001), 0.0, 1.0)
	var forward := to - _anim_from
	if forward.length_squared() > 0.0001:
		_spear.global_transform = Transform3D(_basis_towards(forward), _anim_from.lerp(to, ease(k, 0.4)))

	if _anim_time >= travel_time + hold_time:
		_anim_time = -1.0
		_anim_target = null
		_spear.visible = false
		animation_finished.emit()


static func _basis_towards(direction: Vector3) -> Basis:
	var dir := direction.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(dir, up)


func _rebuild_spear() -> void:
	if _spear:
		_spear.queue_free()
	_spear = spear_scene.instantiate() as Node3D if spear_scene else null
	if _spear == null:
		_spear = _make_spear()
	_spear.name = "Spear"
	_spear.top_level = true
	_spear.visible = false
	add_child(_spear)


func _make_reticle() -> Node3D:
	# Unit-radius ring: a coloured torus on top of a slightly wider black one,
	# so it stays visible on both light and dark backgrounds.
	var root := Node3D.new()
	root.name = "Reticle"
	var edge := 0.08
	root.add_child(_make_ring(1.0 - reticle_thickness - edge, 1.0 + edge, outline_color, 10))
	root.add_child(_make_ring(1.0 - reticle_thickness, 1.0, reticle_color, 11))
	return root


func _make_ring(inner: float, outer: float, color: Color, priority: int) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.material = _overlay_material(color, priority)
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


func _make_beam() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.006, 0.006, 1.0)
	box.material = _overlay_material(Color(reticle_color, 0.7), 9)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = box
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return beam


func _make_spear() -> Node3D:
	# Origin is the spear tip; it points along -Z.
	var root := Node3D.new()

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.015
	shaft_mesh.bottom_radius = 0.015
	shaft_mesh.height = 0.9
	shaft_mesh.material = _plain_material(Color(0.95, 0.95, 0.95))
	var shaft := MeshInstance3D.new()
	shaft.mesh = shaft_mesh
	shaft.rotation.x = -PI / 2.0
	shaft.position.z = 0.15 + 0.45
	root.add_child(shaft)

	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.045
	tip_mesh.height = 0.15
	tip_mesh.material = _plain_material(reticle_color)
	var tip := MeshInstance3D.new()
	tip.mesh = tip_mesh
	tip.rotation.x = -PI / 2.0
	tip.position.z = 0.075
	root.add_child(tip)
	return root


static func _overlay_material(color: Color, priority: int) -> StandardMaterial3D:
	# Drawn on top of everything so the reticle is never hidden.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = priority
	mat.albedo_color = color
	return mat


static func _plain_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
