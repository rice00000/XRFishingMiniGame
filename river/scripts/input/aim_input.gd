class_name AimInput
extends Node
## Where the player aims and when they confirm. The Harpoon only talks to this,
## so supporting a new device (eye tracker, switch button, touch screen) is one
## small subclass. See XRAimInput and DesktopAimInput.

## Emit once per press of the single confirm input.
signal confirm_pressed
## Emit when the experimenter asks for the experiment menu (aborts a running experiment).
signal back_pressed


## Current aim as [origin, direction], or [] when there is nothing to aim with.
func get_aim_ray() -> Array:
	return []


## Where the spear rests before it is thrown (a hand, or just below the camera).
func get_hold_point() -> Vector3:
	var ray := get_aim_ray()
	return ray[0] if not ray.is_empty() else Vector3.ZERO


## Draw a line from the aim origin to the reticle (useful for hand-held pointers).
func wants_beam() -> bool:
	return false


## Short feedback on firing: haptics, rumble, ...
func pulse() -> void:
	pass
