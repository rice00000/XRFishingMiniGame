class_name Harpoon
extends Node3D
## Aim + one confirm input, read from an AimInput (XR controller, mouse/keyboard/
## gamepad, ...). No projectile physics, spread or recoil: on confirm the target is
## chosen immediately (see pick()), `fired` is emitted, and only then does the spear
## animation play. The animation never changes the result.
##
## VR grip throw (in addition to the trigger): the spear sits in the hand while the grip
## is held and leaves with the hand's own velocity when it opens. It then flies under
## gravity, turns its tip into the flight path and only hits a fish it actually reaches;
## `fired` is emitted when it hits (or sinks), with the release time and release ray.
## A held spear also stabs: touching a fish with its tip catches it without throwing.

## Emitted the moment the player confirms. `target` is null on a miss.
signal fired(target: RiverObject, time_usec: int, aim_origin: Vector3, aim_direction: Vector3)
signal animation_finished
## A spear leaves the hand: every trigger shot, and every VR throw with a real swing.
signal launched

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

@export_group("Throw (VR grip)")
## Where the hand holds the shaft, in metres behind the tip.
@export var grip_distance := 0.55
## Release speed multiplier. 1 = exactly the hand's speed; VR throws feel short
## without the spear's weight, so it is boosted (distance grows with its square).
@export_range(0.5, 3.0) var throw_strength := 1.8
## The hand's speed is averaged over this many seconds before it opens.
@export_range(0.02, 0.2) var velocity_window := 0.06
@export var gravity := 9.8
## How quickly (1/s) the flying spear turns its tip into the direction it moves.
@export var align_rate := 6.0
## World height of the water surface. Below it the spear splashes, slows and sinks.
@export var water_height := 0.0
## How strongly water brakes the spear (1/s), and how much of gravity it cancels.
@export var water_drag := 5.0
@export_range(0.0, 1.0) var buoyancy := 0.7
## Seconds a missed spear stays visible under water before it counts as a miss.
@export var sink_time := 1.0
## Seconds a spear stays in the fish it hit.
@export var stuck_time := 0.6
## A throw that neither hits nor reaches the water ends after this long.
@export var max_flight_time := 4.0
@export var splash_color := Color(0.85, 0.95, 1.0)

## Where aim and confirm come from. Set by RiverGame.
var input: AimInput:
	set(value):
		if input and input.confirm_pressed.is_connected(confirm):
			input.confirm_pressed.disconnect(confirm)
			input.grab_started.disconnect(_on_grab_started)
			input.grab_released.disconnect(_on_grab_released)
		input = value
		if input:
			input.confirm_pressed.connect(confirm)
			input.grab_started.connect(_on_grab_started)
			input.grab_released.connect(_on_grab_released)
## Set by RiverGame: confirms are ignored while false.
var enabled := false
## Objects that can be picked. Set by RiverGame.
var candidates: Array[RiverObject] = []
## What would be picked right now (for the reticle).
var hovered: RiverObject

## READY: spear rests at the hold point. HELD: in the hand (VR grip). SHOT: trigger
## animation. FLYING: thrown. STUCK: in the fish it hit.
enum State { READY, HELD, SHOT, FLYING, STUCK }

var _state := State.READY
var _reticle: Node3D
var _beam: MeshInstance3D
var _spear: Node3D
var _splash: CPUParticles3D
var _anim_time := -1.0 # < 0 = not animating
var _anim_from := Vector3.ZERO
var _anim_miss_point := Vector3.ZERO
var _anim_target: RiverObject

var _grab_down := false
var _hand_samples: Array[Vector4] = [] # xyz = hand position, w = time in seconds
var _velocity := Vector3.ZERO
var _center := Vector3.ZERO # the point the hand held, carried along the flight
var _flight_basis := Basis.IDENTITY
var _flight_time := 0.0
var _water_time := -1.0 # < 0 = still above the water
var _release_usec := 0
var _release_origin := Vector3.ZERO
var _release_direction := Vector3.FORWARD
var _stuck_offset := Transform3D.IDENTITY


func _ready() -> void:
	_reticle = _make_reticle()
	_beam = _make_beam()
	for node: Node3D in [_reticle, _beam]:
		node.top_level = true
		node.visible = false
		add_child(node)
	_splash = _make_splash()
	_splash.top_level = true
	add_child(_splash)
	_rebuild_spear()


func _notification(what: int) -> void:
	# RiverGame hides the harpoon when a run stops; drop a thrown or held spear with it.
	if what == NOTIFICATION_VISIBILITY_CHANGED and _spear and not is_visible_in_tree() \
			and _state in [State.HELD, State.FLYING, State.STUCK]:
		_state = State.READY
		_anim_target = null
		_spear.visible = false


## Selects immediately, emits `fired`, then plays the spear animation.
func confirm() -> void:
	if not enabled or not _state in [State.READY, State.HELD] or input == null:
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
	_state = State.SHOT
	_spear.visible = true
	input.pulse()
	launched.emit()


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
	match _state:
		State.SHOT:
			_update_throw(delta)
		State.FLYING:
			_update_flight(delta)
		State.STUCK:
			_update_stuck(delta)
		_:
			_update_aim()


func _update_aim() -> void:
	var ray := input.get_aim_ray() if input else []
	if _state == State.READY and _grab_down:
		_take_spear()
	_spear.visible = _state == State.HELD or (show_held_spear and not ray.is_empty())
	if ray.is_empty() or not enabled:
		hovered = null
		_reticle.visible = false
		_beam.visible = false
		if _state == State.HELD:
			_hold_in_hand()
		elif _spear.visible:
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
	_beam.visible = show_beam and input.wants_beam() and _state != State.HELD and beam_vector.length() > 0.01
	if _beam.visible:
		var beam_basis := _basis_towards(beam_vector).scaled_local(Vector3(1.0, 1.0, beam_vector.length()))
		_beam.global_transform = Transform3D(beam_basis, origin + beam_vector * 0.5)

	if _state == State.HELD:
		_hold_in_hand()
	elif _spear.visible:
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
		_end_spear()


func _on_grab_started() -> void:
	_grab_down = true
	if _state == State.READY:
		_take_spear()


func _on_grab_released() -> void:
	_grab_down = false
	if _state == State.HELD:
		_release()


func _take_spear() -> void:
	if not is_visible_in_tree() or input == null or input.get_aim_ray().is_empty():
		return
	_state = State.HELD
	_hand_samples.clear()
	_spear.visible = true
	input.pulse()


## Puts the spear in the hand and remembers where the hand was, for the release speed.
## A tip that touches a fish on the way stabs it.
func _hold_in_hand() -> void:
	var hand := input.get_hand_transform()
	var old_tip := _spear.global_position
	var had_tip := not _hand_samples.is_empty()
	_spear.global_transform = Transform3D(hand.basis, hand.origin - hand.basis.z * grip_distance)
	var now := Time.get_ticks_usec() / 1_000_000.0
	_hand_samples.append(Vector4(hand.origin.x, hand.origin.y, hand.origin.z, now))
	# Keep one sample older than the window so the average always spans all of it.
	while _hand_samples.size() > 2 and now - _hand_samples[1].w >= velocity_window:
		_hand_samples.pop_front()

	var target := _first_hit(old_tip if had_tip else _spear.global_position, _spear.global_position) if enabled else null
	if target:
		_release_usec = Time.get_ticks_usec()
		_release_origin = hand.origin
		_release_direction = -hand.basis.z
		_flight_basis = hand.basis
		_velocity = _hand_velocity()
		input.pulse()
		_stick_into(target)


func _hand_velocity() -> Vector3:
	if _hand_samples.size() < 2:
		return Vector3.ZERO
	var a := _hand_samples[0]
	var b := _hand_samples[-1]
	var dt := b.w - a.w
	return Vector3(b.x - a.x, b.y - a.y, b.z - a.z) / dt if dt > 0.0 else Vector3.ZERO


func _release() -> void:
	_release_usec = Time.get_ticks_usec()
	_flight_basis = _spear.global_basis.orthonormalized()
	_center = _spear.global_transform * Vector3(0.0, 0.0, grip_distance)
	_velocity = _hand_velocity() * throw_strength
	_release_origin = _center
	_release_direction = _velocity.normalized() if _velocity.length_squared() > 0.0001 else -_flight_basis.z
	_flight_time = 0.0
	_water_time = -1.0
	_state = State.FLYING
	# A slow release just drops the spear; only a real swing makes the throw sound.
	if _velocity.length() > 1.5:
		launched.emit()


func _update_flight(delta: float) -> void:
	_flight_time += delta
	var in_water := _water_time >= 0.0
	_velocity += Vector3.DOWN * gravity * ((1.0 - buoyancy) if in_water else 1.0) * delta
	if in_water:
		_velocity *= exp(-water_drag * delta)
		_water_time += delta
	_center += _velocity * delta
	# Like a javelin, the tip turns into the direction of flight.
	if _velocity.length_squared() > 0.01:
		_flight_basis = _flight_basis.slerp(_basis_towards(_velocity), clampf(align_rate * delta, 0.0, 1.0))
	var old_tip := _spear.global_position
	var tip := _center - _flight_basis.z * grip_distance
	_spear.global_transform = Transform3D(_flight_basis, tip)

	var target := _first_hit(old_tip, tip) if enabled else null
	if target:
		_stick_into(target)
		return
	if not in_water and tip.y <= water_height:
		_water_time = 0.0
		var t := (old_tip.y - water_height) / (old_tip.y - tip.y) if old_tip.y > tip.y else 1.0
		_splash_at(old_tip.lerp(tip, clampf(t, 0.0, 1.0)), _velocity.length())
		_velocity *= 0.5 # the surface takes half the speed
	if _water_time >= sink_time or _flight_time >= max_flight_time:
		fired.emit(null, _release_usec, _release_origin, _release_direction)
		_end_spear()


## The first object whose pick sphere the tip passed through between two frames.
func _first_hit(from: Vector3, to: Vector3) -> RiverObject:
	var best: RiverObject = null
	var best_t := INF
	var segment := to - from
	var length_sq := segment.length_squared()
	for obj in candidates:
		if not is_instance_valid(obj) or obj.caught or not obj.visible:
			continue
		var center := obj.global_position
		var t := clampf((center - from).dot(segment) / length_sq, 0.0, 1.0) if length_sq > 0.0 else 0.0
		if (from + segment * t).distance_to(center) <= obj.get_pick_radius() and t < best_t:
			best = obj
			best_t = t
	return best


func _stick_into(target: RiverObject) -> void:
	# Tip in the middle of the fish, then ride along with it.
	var center := target.global_position
	_spear.global_transform = Transform3D(_flight_basis, center)
	_stuck_offset = target.global_transform.affine_inverse() * _spear.global_transform
	_anim_target = target
	_anim_time = 0.0
	_state = State.STUCK
	if center.y <= water_height + target.get_pick_radius():
		_splash_at(Vector3(center.x, water_height, center.z), _velocity.length())
	fired.emit(target, _release_usec, _release_origin, _release_direction)


func _update_stuck(delta: float) -> void:
	_anim_time += delta
	if is_instance_valid(_anim_target):
		_spear.global_transform = _anim_target.global_transform * _stuck_offset
	if _anim_time >= stuck_time:
		_anim_time = -1.0
		_end_spear()


func _end_spear() -> void:
	_state = State.READY
	_anim_target = null
	_spear.visible = false
	animation_finished.emit()


func _splash_at(point: Vector3, speed: float) -> void:
	_splash.global_position = point
	_splash.initial_velocity_min = clampf(speed * 0.15, 0.6, 2.0)
	_splash.initial_velocity_max = clampf(speed * 0.35, 1.2, 4.0)
	_splash.restart()


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


func _make_splash() -> CPUParticles3D:
	var drop := SphereMesh.new()
	drop.radius = 0.02
	drop.height = 0.04
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = _plain_material(splash_color)
	var splash := CPUParticles3D.new()
	splash.name = "Splash"
	splash.mesh = drop
	splash.emitting = false
	splash.one_shot = true
	splash.amount = 28
	splash.lifetime = 0.8
	splash.explosiveness = 0.95
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	splash.emission_sphere_radius = 0.06
	splash.direction = Vector3.UP
	splash.spread = 30.0
	splash.scale_amount_min = 0.5
	splash.scale_amount_max = 1.3
	return splash


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
