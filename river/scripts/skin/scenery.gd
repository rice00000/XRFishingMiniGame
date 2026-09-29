class_name Scenery
extends Node3D
## Root of a backdrop scene. While in the tree it copies `environment` (sky, fog,
## tonemap, ...) onto the world's current Environment, and restores the original on
## exit, so removing the scenery brings the old look back. Copying onto the existing
## Environment (instead of replacing it) keeps things like XRPassthrough working.

@export var environment: Environment

var _target: Environment
var _saved := {}


func _ready() -> void:
	if environment == null:
		return
	_target = get_viewport().find_world_3d().environment
	if _target == null:
		var world_environment := WorldEnvironment.new()
		world_environment.environment = environment
		add_child(world_environment)
		return
	for property in environment.get_property_list():
		var key: String = property.name
		if property.usage & PROPERTY_USAGE_STORAGE and not key.begins_with("resource_") and key != "script":
			_saved[key] = _target.get(key)
			_target.set(key, environment.get(key))


func _exit_tree() -> void:
	for key in _saved:
		_target.set(key, _saved[key])
	_saved.clear()
