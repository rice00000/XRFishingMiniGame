class_name RiverObjectConfig
extends Resource
## One kind of floating object.
## Gameplay only reads the "Motion" values; the "Visual" group is cosmetic, so a
## placeholder can be swapped for any imported model (.glb/.gltf/.tscn) by setting
## `scene`, without touching any code.

enum Shape { SPHERE, BOX, CYLINDER, CAPSULE, CONE, TORUS }

## Stable id used by rules, rewards and logs. Empty = the resource file name.
@export var id: StringName
@export var display_name := ""
## Free-form labels for custom rules (see TagRule), e.g. "red", "fish".
@export var tags: PackedStringArray

@export_group("Visual")
## Any scene or imported model. Leave empty to use the placeholder shape below.
@export var scene: PackedScene
@export var placeholder_shape := Shape.SPHERE
@export var placeholder_color := Color(1.0, 0.15, 0.1)
## Adds a contrasting block on one side so spinning is visible on symmetric shapes.
@export var placeholder_marker := true
## Largest dimension of the visual in metres. Imported models are scaled to fit.
@export var size := 0.45
## Scale imported models to `size`. Off = keep the model's own scale.
@export var fit_model_to_size := true
## Fixes an imported model's orientation / pivot. Does not affect motion.
@export var model_rotation_degrees := Vector3.ZERO
@export var model_offset := Vector3.ZERO
## Selection radius in metres. 0 = automatic (half of `size`).
@export var pick_radius := 0.0

@export_group("Motion")
## Metres per second along the river. 0 = stationary, negative = upstream.
@export var movement_speed := 0.3
## Degrees per second around rotation_axis. 0 = no spin.
@export var rotation_speed := 0.0
@export var rotation_axis := Vector3.UP
## Starting orientation (tilt) in degrees, applied before spinning.
@export var initial_rotation_degrees := Vector3.ZERO
## Height of the object's centre above the water surface.
@export var float_height := 0.15


func get_id() -> StringName:
	if id != &"":
		return id
	return StringName(resource_path.get_file().get_basename())


func get_pick_radius() -> float:
	return pick_radius if pick_radius > 0.0 else size * 0.5
