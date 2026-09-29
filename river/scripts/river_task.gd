class_name RiverTask
extends Resource
## One trial. "Presentation" is only read by TaskUI; "Answer" is only read by the rule.

## Used in logs. Empty = the resource file name.
@export var id: StringName

@export_group("Presentation")
@export_multiline var text := ""
@export var reference_image: Texture2D
## Shows reference_object as a still 3D model next to the text (handy with placeholders).
@export var show_reference_model := false
## The object the task talks about. Also the default for SAME_AS_REFERENCE rules.
@export var reference_object: RiverObjectConfig

@export_group("Answer")
@export var rule: TaskRule
@export var pools: Array[SpawnPool] = []

@export_group("Trial")
## Fixed seed for this trial's layout. -1 = derived from the session seed.
@export var fixed_seed := -1
## Keep trying after a wrong catch (every catch is still logged).
@export var retry_until_correct := false
## Seconds before the trial ends as "timeout". 0 = no limit.
@export var time_limit := 0.0


func get_id() -> StringName:
	if id != &"":
		return id
	return StringName(resource_path.get_file().get_basename())
