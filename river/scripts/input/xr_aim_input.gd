class_name XRAimInput
extends AimInput
## VR: aim with a tracked controller's -Z axis, confirm with one controller button.

@export var controller: XRController3D
## OpenXR action that fires.
@export var confirm_action := &"trigger_click"
@export var haptics := true
## Controller whose `back_action` opens the experiment menu (the left hand's menu button).
@export var back_controller: XRController3D
@export var back_action := &"menu_button"


func _ready() -> void:
	if controller:
		controller.button_pressed.connect(_on_button_pressed)
	if back_controller:
		back_controller.button_pressed.connect(_on_back_button_pressed)


func get_aim_ray() -> Array:
	if controller == null or not controller.get_has_tracking_data():
		return []
	return [controller.global_position, -controller.global_basis.z.normalized()]


func wants_beam() -> bool:
	return true


func pulse() -> void:
	if haptics and controller:
		controller.trigger_haptic_pulse(&"haptic", 0.0, 0.5, 0.1, 0.0)


func _on_button_pressed(action: String) -> void:
	if action == confirm_action:
		confirm_pressed.emit()


func _on_back_button_pressed(action: String) -> void:
	if action == back_action:
		back_pressed.emit()
