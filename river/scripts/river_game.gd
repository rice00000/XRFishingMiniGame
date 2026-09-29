class_name RiverGame
extends Node3D
## Runs a RiverSession. Per trial: spawn the task's pools with a seeded RNG, ask the
## rule for the correct targets, show the task, wait for a harpoon selection, then
## log it, grant rewards and move on.

signal session_finished

@export var session: RiverSession
@export var autostart := true
## Visual look (scenery, object models, spear). Empty = plain placeholders.
@export var skin: RiverSkin
## Hidden while the skin's scenery is shown (e.g. the template's floor and table).
@export var hide_with_scenery: Array[NodePath] = []

@export_group("Nodes")
@export var spawner: RiverSpawner
@export var harpoon: Harpoon
@export var task_ui: TaskUI
@export var inventory: Inventory
@export var logger: TrialLogger

@export_group("Input")
## Any AimInput node to use instead of the automatic choice
## (XR controller with a headset, otherwise mouse / keyboard / gamepad).
@export var input_override: AimInput
## Controller that aims and fires in XR.
@export var aim_controller: XRController3D
## Camera used for aiming on PC / Mac.
@export var camera: Camera3D

@export_group("Desktop view (PC, Mac)")
## Camera height and downward tilt when no headset is running.
@export var desktop_eye_height := 1.3
@export var desktop_pitch_degrees := -14.0

var session_seed := 0
var current_task: RiverTask
var targets: Array[RiverObject] = []

var _tasks: Array[RiverTask] = []
var _rng := RandomNumberGenerator.new()
var _trial := -1
var _trial_start_usec := 0
var _accepting := false


func _ready() -> void:
	_apply_skin()
	harpoon.fired.connect(_on_harpoon_fired)
	inventory.changed.connect(func(_item: StringName, _total: int) -> void: task_ui.show_inventory(inventory.items))
	if autostart:
		# Deferred so Main has decided whether XR is running.
		start_session.call_deferred()


func start_session() -> void:
	if session == null or session.tasks.is_empty():
		push_error("RiverGame|ERROR: no session or the session has no tasks")
		return
	session_seed = session.fixed_seed if session.fixed_seed >= 0 else randi()
	_rng.seed = session_seed
	_tasks = session.tasks.duplicate()
	if session.shuffle_tasks:
		SpawnPool.shuffle(_tasks, _rng)
	_trial = -1

	inventory.clear()
	task_ui.show_inventory(inventory.items)
	if harpoon.input == null:
		harpoon.input = _make_input()

	logger.start_session(session_seed, session)
	_next_trial()


func _process(_delta: float) -> void:
	if _accepting and current_task.time_limit > 0.0 \
			and Time.get_ticks_usec() - _trial_start_usec >= current_task.time_limit * 1_000_000.0:
		_set_accepting(false)
		_finish_trial("timeout", session.timeout_text, false)


func _next_trial() -> void:
	_trial += 1
	if _trial >= _tasks.size():
		_end_session()
		return
	current_task = _tasks[_trial]

	# Always drawn, so a fixed-seed task doesn't shift the seeds of later trials.
	var derived_seed := _rng.randi()
	var trial_seed := current_task.fixed_seed if current_task.fixed_seed >= 0 else derived_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = trial_seed

	var objects := spawner.spawn(current_task.pools, rng)
	targets.clear()
	if current_task.rule:
		targets = current_task.rule.find_targets(objects, current_task)
	if targets.is_empty():
		push_warning("RiverGame|WARN: task '%s' has no correct target in this layout" % current_task.get_id())

	harpoon.candidates = objects
	var preview: RiverObjectConfig = current_task.reference_object if current_task.show_reference_model else null
	task_ui.show_task(current_task.text, current_task.reference_image, preview)

	_trial_start_usec = Time.get_ticks_usec()
	logger.begin_trial(_trial, current_task, trial_seed, objects, targets, _trial_start_usec)
	_set_accepting(true)


func _on_harpoon_fired(target: RiverObject, time_usec: int, aim_origin: Vector3, aim_direction: Vector3) -> void:
	if not _accepting:
		return
	if target == null:
		logger.log_miss(time_usec, aim_origin, aim_direction)
		return

	# The answer is decided here, before the animation plays.
	_set_accepting(false)
	target.caught = true
	var correct := targets.has(target)
	logger.log_selection(target, correct, time_usec, aim_origin, aim_direction)

	await harpoon.animation_finished
	target.visible = false
	if session.reward_table:
		var rewards := session.reward_table.rewards_for(target, correct)
		for item in rewards:
			inventory.add(item, rewards[item])
		logger.log_rewards(rewards)

	if correct or not current_task.retry_until_correct:
		var feedback := session.correct_text if correct else session.wrong_text
		if correct and session.show_time_on_correct:
			feedback += "\n%.2f s" % ((time_usec - _trial_start_usec) / 1_000_000.0)
		_finish_trial("correct" if correct else "wrong", feedback, correct)
	else:
		await _show_feedback(session.wrong_text, false)
		_set_accepting(true)


func _finish_trial(outcome: String, feedback: String, positive: bool) -> void:
	logger.end_trial(outcome)
	await _show_feedback(feedback, positive)
	task_ui.hide_task()
	spawner.clear()
	await get_tree().create_timer(session.pause_between_trials).timeout
	_next_trial()


func _show_feedback(text: String, positive: bool) -> void:
	if text.is_empty():
		return
	task_ui.show_feedback(text, positive)
	await get_tree().create_timer(session.feedback_seconds).timeout
	task_ui.hide_feedback()


func _end_session() -> void:
	_set_accepting(false)
	current_task = null
	task_ui.show_task(session.end_text)
	logger.end_session(inventory.items)
	session_finished.emit()


## XR controller when a headset is running, otherwise mouse / keyboard / gamepad.
func _make_input() -> AimInput:
	if input_override:
		return input_override
	var input: AimInput
	if get_viewport().use_xr:
		var xr := XRAimInput.new()
		xr.controller = aim_controller
		input = xr
	else:
		var desktop := DesktopAimInput.new()
		desktop.camera = camera
		input = desktop
		if camera:
			camera.position.y = desktop_eye_height
			camera.rotation_degrees.x = desktop_pitch_degrees
	input.name = "Input"
	add_child(input)
	return input


func _apply_skin() -> void:
	spawner.skin = skin
	task_ui.skin = skin
	if skin == null:
		return
	if skin.spear_scene:
		harpoon.spear_scene = skin.spear_scene
	if skin.scenery:
		var scenery := skin.scenery.instantiate()
		scenery.name = "Scenery"
		add_child(scenery)
		spawner.set_water_visible(false)
		for path in hide_with_scenery:
			var node := get_node_or_null(path)
			if node:
				node.set("visible", false)
				node.process_mode = Node.PROCESS_MODE_DISABLED


func _set_accepting(value: bool) -> void:
	_accepting = value
	harpoon.enabled = value
