class_name RiverSkin
extends Resource
## The look of the game, kept apart from gameplay. Assign one on RiverGame to dress
## the game up; clear it to get the plain high-contrast placeholder version back.
## Rules, rewards and logs never read it (logs do record which visual was shown).

## Backdrop scene: water, shore, sky, props. Use a Scenery node as its root to also
## change the sky / lighting.
@export var scenery: PackedScene
## Object id -> model scene. Objects without an entry keep their config's own visual.
## Models are scaled to the config's `size`; wrap them in a SkinModel scene to fix
## orientation or loop an animation.
@export var object_scenes: Dictionary[StringName, PackedScene] = {}
## Thrown spear. Tip at the origin, pointing -Z. Empty = built-in simple spear.
@export var spear_scene: PackedScene


func scene_for(cfg: RiverObjectConfig) -> PackedScene:
	return object_scenes.get(cfg.get_id())
