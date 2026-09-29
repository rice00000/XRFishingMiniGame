class_name DesktopAimInput
extends AimInput
## PC / Mac: a screen cursor aims through the camera. The mouse moves it directly;
## arrow keys / WASD / a gamepad stick move it too, so the game also works without
## a mouse. Fire = left click, Space, Enter or gamepad A (all remappable in
## Project Settings > Input Map; defaults are added only if the actions are missing).

const FIRE := &"harpoon_fire"
const LEFT := &"harpoon_aim_left"
const RIGHT := &"harpoon_aim_right"
const UP := &"harpoon_aim_up"
const DOWN := &"harpoon_aim_down"

@export var camera: Camera3D
## Cursor speed for keys / sticks, in screen heights per second.
@export var key_aim_speed := 0.6
## Where the spear rests, relative to the camera (right, up, back).
@export var hold_offset := Vector3(0.42, -0.4, 0.05)
## The reticle replaces the system cursor.
@export var hide_system_cursor := true

## Cursor position in viewport pixels.
var cursor := Vector2.ZERO


func _ready() -> void:
	add_default_actions()
	cursor = get_viewport().get_visible_rect().get_center()
	if hide_system_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _exit_tree() -> void:
	if hide_system_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		cursor = get_viewport().get_mouse_position()
	elif event.is_action_pressed(FIRE):
		confirm_pressed.emit()


func _process(delta: float) -> void:
	var move := Input.get_vector(LEFT, RIGHT, UP, DOWN)
	if move != Vector2.ZERO:
		var rect := get_viewport().get_visible_rect()
		cursor = (cursor + move * rect.size.y * key_aim_speed * delta).clamp(rect.position, rect.end)


func get_aim_ray() -> Array:
	var cam := camera if camera else get_viewport().get_camera_3d()
	if cam == null:
		return []
	return [cam.project_ray_origin(cursor), cam.project_ray_normal(cursor)]


func get_hold_point() -> Vector3:
	# Just below and right of the eye, like holding the spear at the shoulder.
	var cam := camera if camera else get_viewport().get_camera_3d()
	return cam.global_transform * hold_offset if cam else Vector3.ZERO


func pulse() -> void:
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, 0.3, 0.6, 0.12)


## Adds default bindings for any harpoon action the project doesn't define.
static func add_default_actions() -> void:
	_ensure(FIRE, [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_SPACE), _key(KEY_ENTER), _pad(JOY_BUTTON_A)])
	_ensure(LEFT, [_key(KEY_LEFT), _key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_ensure(RIGHT, [_key(KEY_RIGHT), _key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_ensure(UP, [_key(KEY_UP), _key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_ensure(DOWN, [_key(KEY_DOWN), _key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])


static func _ensure(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for event in events:
		InputMap.action_add_event(action, event)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
