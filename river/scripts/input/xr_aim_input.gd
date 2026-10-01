class_name XRAimInput
extends AimInput
## VR: aim with a tracked controller's -Z axis, confirm with one controller button.
## Throwing: hold the grip button to take the spear in hand, swing and let go.

@export var controller: XRController3D
## OpenXR action that fires.
@export var confirm_action := &"trigger_click"
@export var haptics := true
## Controller whose `back_action` opens the experiment menu (the left hand's menu button).
@export var back_controller: XRController3D
@export var back_action := &"menu_button"

@export_group("Throw")
## OpenXR action that holds the spear; letting go throws it (the Quest grip button).
## Empty = no throwing.
@export var grab_action := &"grip_click"
## Controller (grip pose) whose position is the palm holding the spear. The spear points
## along `controller` (the aim ray). Empty = held at `controller`.
@export var hand_controller: XRController3D


func _ready() -> void:
	if controller:
		controller.button_pressed.connect(_on_button_pressed)
		controller.button_released.connect(_on_button_released)
	if back_controller:
		back_controller.button_pressed.connect(_on_back_button_pressed)


func get_aim_ray() -> Array:
	if controller == null or not controller.get_has_tracking_data():
		return []
	return [controller.global_position, -controller.global_basis.z.normalized()]


func get_hand_transform() -> Transform3D:
	if controller == null:
		return Transform3D.IDENTITY
	# Points like the aim ray (roughly square to the handle), held at the palm.
	var t := controller.global_transform.orthonormalized()
	if hand_controller and hand_controller.get_has_tracking_data():
		t.origin = hand_controller.global_position
	return t


func wants_beam() -> bool:
	return true


func pulse() -> void:
	if haptics and controller:
		controller.trigger_haptic_pulse(&"haptic", 0.0, 0.5, 0.1, 0.0)


func _on_button_pressed(action: String) -> void:
	if action == confirm_action:
		confirm_pressed.emit()
	elif action == grab_action and not grab_action.is_empty():
		grab_started.emit()


func _on_button_released(action: String) -> void:
	if action == grab_action and not grab_action.is_empty():
		grab_released.emit()


func _on_back_button_pressed(action: String) -> void:
	if action == back_action:
		back_pressed.emit()
