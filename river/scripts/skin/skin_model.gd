class_name SkinModel
extends Node3D
## Optional root for a skin model scene: put the imported model under it, rotate the
## model so it faces +X (downstream), and this plays its animation on a loop.

## Empty = the first animation found.
@export var animation := &""
@export var speed_scale := 1.0


func _ready() -> void:
	var players := find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	var anim_name := String(animation)
	if anim_name.is_empty():
		var names := player.get_animation_list()
		if names.is_empty():
			return
		anim_name = names[0]
	player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	player.speed_scale = speed_scale
	player.play(anim_name)
