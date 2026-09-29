@tool
class_name RiverObjectConfig
extends Resource
## One kind of floating object: what it looks like, how it moves, and optionally
## one value to vary. Gameplay only reads the motion and selection settings; the look is cosmetic, so a
## placeholder shape can be swapped for any model (.glb/.gltf/.tscn) via `scene`.

## Shown in the logs, e.g. "red_ball". Rewards and skins can match it too.
## Leave empty to use the shape name ("capsule"); give objects a name when you
## need to tell two of the same shape apart.
@export var name: StringName
## Free-form labels, e.g. "red", "still". Used by the "has tag" rule.
@export var tags: PackedStringArray

@export_group("Look")
## Used when `scene` is empty. A skin may replace it with a model.
@export_enum("sphere", "box", "cylinder", "capsule", "cone", "torus") var shape := "sphere"
@export var color := Color(1.0, 0.15, 0.1)
## Largest dimension in metres. Models are scaled to fit.
@export var size := 0.45
## A model to show instead of the shape (a stimulus, e.g. a character).
@export var scene: PackedScene
## 2D picture of this object, shown on the task panel when the task refers to it.
@export var picture: Texture2D
## Adds a contrasting block on one side of the shape so spinning is visible.
@export var show_spin_marker := true

@export_group("Default motion (base values)")
## Metres per second along the river. 0 = stays in place, negative = upstream.
## Replaced by the "Independent variable" values when that varies this property.
@export var swim_speed_m_per_s := 0.3
## Degrees per second. 0 = no spin. Replaced by the "Independent variable" values
## when that varies this property.
@export var spin_speed_deg_per_s := 0.0
## Height of the object's centre above the water.
@export var float_height := 0.15

@export_group("Independent variable (overrides the default above)")
## Makes one copy of this object per value in `variable_values`, with the chosen
## property set to that value and "_<value>" added to the name: fish -> fish_0.15,
## fish_0.3, ... The default value of that property above is ignored.
## Use values in the property's own unit (m/s, degrees/s, metres).
@export_enum("none", "swim_speed_m_per_s", "spin_speed_deg_per_s", "size", "float_height") var variable := "none"
@export var variable_values: PackedFloat64Array = []

@export_group("Spin direction")
## The axis the object spins around.
@export var spin_axis := Vector3.UP
## Starting orientation (tilt) in degrees, applied before spinning.
@export var start_tilt_degrees := Vector3.ZERO

@export_group("Model import fixes")
## Scale `scene` to `size`. Off = keep the model's own scale.
@export var scale_model_to_size := true
## Fixes an imported model's orientation. Does not affect motion.
@export var model_orientation_fix_degrees := Vector3.ZERO
## Fixes an imported model's pivot. Does not affect motion.
@export var model_offset_fix_m := Vector3.ZERO

@export_group("Selection")
## How close the aim must be to select this object, as a radius in metres.
## 0 = automatic (half of `size`).
@export var selection_radius_m := 0.0

## Set on copies made by `variable`: the name of the object they were made from.
var variant_of: StringName


func get_id() -> StringName:
	if name != &"":
		return name
	if resource_path != "" and not resource_path.contains("::"):
		return StringName(resource_path.get_file().get_basename())
	return StringName(shape)


func get_pick_radius() -> float:
	return selection_radius_m if selection_radius_m > 0.0 else size * 0.5


## This object, or one copy per level when `variable` is set.
func expand() -> Array[RiverObjectConfig]:
	var result: Array[RiverObjectConfig] = []
	if variable == "none" or variable_values.is_empty():
		result.append(self)
		return result
	for level in variable_values:
		var copy: RiverObjectConfig = duplicate()
		copy.name = StringName("%s_%s" % [get_id(), String.num(level)])
		copy.variant_of = get_id()
		copy.variable = "none"
		copy.set(variable, level)
		result.append(copy)
	return result
