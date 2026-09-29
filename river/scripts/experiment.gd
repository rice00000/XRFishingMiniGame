@tool
class_name Experiment
extends Resource
## One experiment = one .tres file in res://river/experiments/. It holds everything:
## the look, the tasks, their objects (embedded), trial order and feedback. The
## in-game menu lists every file in that folder, sorted by file name, and shows the
## file name as the experiment's name, so name files for what they test:
## "01_fastest_of_five_identical_fish.tres" -> "01 Fastest of five identical fish".

const FOLDER := "res://river/experiments"

## What this experiment tests. Shown in the menu and written to the logs.
@export_multiline var description := """NEW EXPERIMENT: replace this text with what it tests.
Simplest: it already runs. Edit the task's question_text, correct_answer_rule and repeat_times.
Objects: objects_in_trial. `variable` + `variable_values` makes one object at several speeds.
Next: add more tasks, extra_pools (distractors), reference_object / each_object_as_reference
(find this picture), time_limit, custom_rule. Details: river/README.md"""
## The tasks, each with its own objects and `repeat_times`.
@export var tasks: Array[RiverTask] = []
## Mix the trials of all tasks into a random order.
@export var shuffle_trial_order := false
## Visual look (scenery, object models, spear). New experiments start with the lagoon;
## clear it for plain high-contrast shapes.
@export var look: RiverSkin = preload("res://river/skins/lagoon/lagoon_skin.tres")

@export_group("Feedback")
## Empty text = show nothing.
@export var correct_text := "Great catch!"
## Adds the time from trial start to the catch (e.g. "1.84 s") under the correct text.
@export var show_time_on_correct := false
@export var wrong_text := "Not that one"
@export var timeout_text := ""
@export var end_text := "All done!"
@export var feedback_seconds := 1.5
@export var pause_between_trials := 1.0

@export_group("Advanced")
## Items granted per catch, shown to the player as a small inventory.
@export var reward_table: RewardTable
## Seed for the whole run. -1 = new random seed each run.
## The seed is always logged, so any run can be replayed by entering it here.
@export var fixed_seed := -1


func _init() -> void:
	# A brand-new experiment made in the editor comes with one filled-in task, so it
	# runs as soon as it is saved. Files being loaded overwrite this.
	if Engine.is_editor_hint():
		var starter: Array[RiverTask] = [RiverTask.new()]
		tasks = starter


## File name without the order number, for logs: "fastest_of_five_identical_fish".
func get_id() -> String:
	var file := resource_path.get_file().get_basename()
	var regex := RegEx.create_from_string("^\\d+[_ -]+")
	return regex.sub(file, "")


## The name shown in the menu: the file name with spaces, "01 Fastest of five identical fish".
func get_title() -> String:
	var words := resource_path.get_file().get_basename().split("_", false)
	for i in words.size():
		if not words[i].is_valid_int():
			words[i] = words[i].left(1).to_upper() + words[i].substr(1)
			break
	return " ".join(words)


## The trial list for one run: every task's trials, shuffled with `rng` if `shuffle_trial_order`.
func build_trials(rng: RandomNumberGenerator) -> Array[RiverTask]:
	_name_tasks()
	var trials: Array[RiverTask] = []
	for task in tasks:
		if task:
			trials.append_array(task.expand())
	if shuffle_trial_order:
		SpawnPool.shuffle(trials, rng)
	return trials


## Setup mistakes worth fixing before running participants.
func problems() -> PackedStringArray:
	_name_tasks()
	var result := PackedStringArray()
	if tasks.is_empty():
		result.append("has no tasks")
	var seen := {}
	for task in tasks:
		if task == null:
			result.append("has an empty task slot")
			continue
		if task.get_pools().is_empty():
			result.append("task '%s' has no objects" % task.get_id())
		if task.correct_answer_rule == "custom" and task.custom_rule == null:
			result.append("task '%s' uses a custom rule but none is set" % task.get_id())
		if task.correct_answer_rule == "has tag" and task.correct_tag.is_empty():
			result.append("task '%s' uses 'has tag' but the tag is empty" % task.get_id())
		if task.correct_answer_rule == "same as reference" and task.reference_object == null and not task.each_object_as_reference:
			result.append("task '%s' compares to a reference but has none" % task.get_id())
		for pool in task.get_pools():
			if pool == null:
				continue
			for cfg in pool.get_objects():
				var key := cfg.get_id()
				if seen.has(key) and seen[key] != cfg and cfg.variant_of == &"":
					result.append("two different objects share the name '%s'" % key)
				seen[key] = cfg
	return result


## Unnamed tasks become "task1", "task2", ... by position, and unnamed objects take
## their shape name ("capsule", "capsule_2", ...), so logs can tell them apart.
func _name_tasks() -> void:
	var taken := {}
	var unnamed: Array[RiverObjectConfig] = []
	for i in tasks.size():
		var task := tasks[i]
		if task == null:
			continue
		if task.name == &"":
			task.name = StringName("task%d" % (i + 1))
		var pools: Array[SpawnPool] = task.get_pools()
		for pool in pools:
			for cfg in pool.objects:
				if cfg == null:
					continue
				if cfg.name != &"":
					taken[cfg.name] = true
				elif not unnamed.has(cfg):
					unnamed.append(cfg)
	for cfg in unnamed:
		var base := String(cfg.get_id())
		var candidate := base
		var n := 2
		while taken.has(StringName(candidate)):
			candidate = "%s_%d" % [base, n]
			n += 1
		taken[StringName(candidate)] = true
		cfg.name = StringName(candidate)


## Every Experiment in `folder`, sorted by file name.
static func load_all(folder := FOLDER) -> Array[Experiment]:
	var result: Array[Experiment] = []
	var files := Array(ResourceLoader.list_directory(folder))
	files.sort()
	for file: String in files:
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var experiment := load(folder.path_join(file)) as Experiment
		if experiment:
			result.append(experiment)
	return result
