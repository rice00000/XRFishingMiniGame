class_name RiverSkin
extends Resource
## The look of the game, kept apart from gameplay. An Experiment picks one to dress
## the game up; leave it empty to get the plain high-contrast placeholder version.
## Rules, rewards and logs never read it (logs do record which visual was shown).
##
## Which model an object gets: its entry in `object_scenes`, else its own `scene`
## (a stimulus model), else the model for its placeholder shape, else the placeholder.
## So new experiments built from placeholder shapes are dressed up automatically.

## Backdrop scene: water, shore, sky, props. Use a Scenery node as its root to also
## change the sky / lighting.
@export var scenery: PackedScene
## Thrown spear. Tip at the origin, pointing -Z. Empty = built-in simple spear.
@export var spear_scene: PackedScene

@export_group("Placeholder shape -> model")
## Models are scaled to the config's `size`; wrap them in a SkinModel scene to fix
## orientation or loop an animation.
@export var sphere: PackedScene
@export var box: PackedScene
@export var cylinder: PackedScene
@export var capsule: PackedScene
@export var cone: PackedScene
@export var torus: PackedScene

@export_group("Exceptions")
## Object name -> model, overriding everything above. A varied copy (fish_0.3) also
## matches the name it was made from (fish).
@export var object_scenes: Dictionary[StringName, PackedScene] = {}


func scene_for(cfg: RiverObjectConfig) -> PackedScene:
	for key in [cfg.get_id(), cfg.variant_of]:
		if object_scenes.has(key):
			return object_scenes[key]
	if cfg.scene:
		return null
	return get(cfg.shape) as PackedScene
