@tool
class_name RiverTask
extends Resource
## One kind of trial: the question, what counts as correct, and which objects float by.

## What the player reads on the panel.
@export_multiline var question_text := "Catch the fish that swims the FASTEST!"
## Which spawned objects are correct answers.
@export_enum("fastest moving", "slowest moving", "fastest spinning", "slowest spinning",
		"same as reference", "has tag", "custom") var correct_answer_rule := "fastest moving"
## For "has tag": objects with this tag are correct.
@export var correct_tag := ""
## The objects that float by in each trial.
@export var objects_in_trial: Array[RiverObjectConfig] = []:
	set(value):
		objects_in_trial = value
		_starter_fish = false
## How many of `objects_in_trial` spawn per trial, each at most once. 0 = all of them.
@export_range(0, 50) var objects_per_trial := 0
## How many times this task runs in the experiment. 0 = skip it.
@export_range(0, 100) var repeat_times := 1

@export_group("Reference (shown on the panel)")
## The object the task is about. Used by "same as reference"; its `picture` is shown.
@export var reference_object: RiverObjectConfig
## One trial per object in `objects_in_trial`, each using that object as the reference
## ("find this one", for every character). Multiplied by `repeat_times`.
@export var each_object_as_reference := false
## Shows the reference object as a still 3D model next to the text.
@export var show_reference_model := false
## Picture on the panel. Empty = the reference object's picture.
@export var reference_image: Texture2D

@export_group("Trial")
## Seconds before the trial ends as "timeout". 0 = no limit.
@export var time_limit := 0.0
## Keep trying after a wrong catch (every catch is still logged).
@export var retry_until_correct := false

@export_group("Advanced")
## Name in the logs. Empty = "task1", "task2", ... by position in the experiment.
@export var name: StringName
## More groups to spawn alongside `objects_in_trial`, each with its own count (e.g. 1 fixed
## target + 3 random distractors). Rewards can match a group's id.
@export var extra_pools: Array[SpawnPool] = []:
	set(value):
		extra_pools = value
		# A loaded task that uses only extra pools must not keep the starter fish.
		if _starter_fish and not value.is_empty():
			objects_in_trial = []
			_starter_fish = false
## Used when the rule is "custom". Any script that extends TaskRule.
@export var custom_rule: TaskRule
## Fixed seed for this task's layouts. -1 = derived from the experiment seed.
@export var fixed_layout_seed := -1

var _pools: Array[SpawnPool] = []
var _rule: TaskRule
var _starter_fish := false


func _init() -> void:
	# A brand-new task made in the editor comes with five identical fish at five
	# speeds, matching the default text and rule. Files being loaded overwrite this.
	if Engine.is_editor_hint():
		var fish := RiverObjectConfig.new()
		fish.name = &"fish"
		fish.shape = "capsule"
		fish.color = Color(1, 0.45, 0.1)
		fish.size = 0.6
		fish.float_height = 0.08
		fish.variable = "swim_speed_m_per_s"
		fish.variable_values = PackedFloat64Array([0.15, 0.3, 0.45, 0.6, 0.75])
		var starter: Array[RiverObjectConfig] = [fish]
		objects_in_trial = starter
		_starter_fish = true  # after the assignment, which clears it


func get_id() -> StringName:
	return name if name != &"" else &"task"


## `objects_in_trial` as a pool (name = the task name), followed by `extra_pools`.
func get_pools() -> Array[SpawnPool]:
	if _pools.is_empty():
		if not objects_in_trial.is_empty():
			var own := SpawnPool.new()
			own.name = get_id()
			own.objects = objects_in_trial
			own.count = objects_per_trial
			_pools.append(own)
		for pool in extra_pools:
			if pool:
				_pools.append(pool)
	return _pools


func get_rule() -> TaskRule:
	if _rule == null:
		match correct_answer_rule:
			"custom":
				_rule = custom_rule
			"has tag":
				var tag_rule := TagRule.new()
				tag_rule.tag = correct_tag
				_rule = tag_rule
			_:
				var standard := StandardRule.new()
				standard.kind = {
					"fastest moving": StandardRule.Kind.FASTEST_MOVEMENT,
					"slowest moving": StandardRule.Kind.SLOWEST_MOVEMENT,
					"fastest spinning": StandardRule.Kind.FASTEST_ROTATION,
					"slowest spinning": StandardRule.Kind.SLOWEST_ROTATION,
					"same as reference": StandardRule.Kind.SAME_AS_REFERENCE,
				}[correct_answer_rule]
				_rule = standard
	return _rule


## The rule as written in the logs, e.g. "fastest moving" or "has tag: red".
func describe_rule() -> String:
	match correct_answer_rule:
		"has tag":
			return "has tag: " + correct_tag
		"custom":
			return custom_rule.describe() if custom_rule else "custom (none set)"
	return correct_answer_rule


func get_reference_image() -> Texture2D:
	if reference_image:
		return reference_image
	return reference_object.picture if reference_object else null


## The trials this task contributes to an experiment, in order (before shuffling).
func expand() -> Array[RiverTask]:
	var one_round: Array[RiverTask] = [self]
	if each_object_as_reference:
		one_round.clear()
		var pools := get_pools()
		if pools.is_empty():
			push_warning("RiverTask|WARN: '%s' uses each_object_as_reference but has no objects" % get_id())
		else:
			for cfg in pools[0].get_objects():
				var trial: RiverTask = duplicate()
				trial._pools = pools
				trial.reference_object = cfg
				trial.each_object_as_reference = false
				one_round.append(trial)
	var result: Array[RiverTask] = []
	for i in repeat_times:
		result.append_array(one_round)
	return result
