class_name RiverGame
extends Node3D
## Shows the experiment menu, then runs the chosen Experiment. Per trial: spawn the
## task's objects with a seeded RNG, ask the rule for the correct targets, show the task,
## wait for a harpoon selection, then log it, grant rewards and move on. The menu
## button (Esc on PC) stops a run and goes back to the menu.
##
## Command line (after `--`): --experiment=<id> starts that experiment straight away,
## --participant=<n> sets the participant number.

## Hidden while an experiment's skin shows its scenery (e.g. the template's floor and table).
@export var hide_with_scenery: Array[NodePath] = []
## Seconds the end text stays up before the menu comes back.
@export var end_screen_seconds := 3.0

@export_group("Nodes")
@export var spawner: RiverSpawner
@export var harpoon: Harpoon
@export var task_ui: TaskUI
@export var inventory: Inventory
@export var collection: CollectionBoard
@export var logger: TrialLogger
@export var menu: ExperimentMenu

@export_group("Input")
## Any AimInput node to use instead of the automatic choice
## (XR controller with a headset, otherwise mouse / keyboard / gamepad).
@export var input_override: AimInput
## Controller that aims and fires in XR.
@export var aim_controller: XRController3D
## Controller whose menu button opens the experiment menu in XR.
@export var menu_controller: XRController3D
## Controller (grip pose) the spear sits in while the grip button holds it in XR.
@export var hand_controller: XRController3D
## Camera used for aiming on PC / Mac.
@export var camera: Camera3D

@export_group("Desktop view (PC, Mac)")
## Camera height and downward tilt when no headset is running.
@export var desktop_eye_height := 1.3
@export var desktop_pitch_degrees := -14.0

var experiment: Experiment
var session_seed := 0
var current_task: RiverTask
var targets: Array[RiverObject] = []

var _trials: Array[RiverTask] = []
var _rng := RandomNumberGenerator.new()
var _trial := -1
var _trial_start_usec := 0
var _accepting := false
## Bumped whenever a run starts or stops, so awaits from an older run stop quietly.
var _run := 0
var _scenery: Node


func _ready() -> void:
	harpoon.fired.connect(_on_harpoon_fired)
	harpoon.launched.connect(GameAudio.play.bind(&"throw"))
	menu.chosen.connect(start_experiment)
	# Deferred so Main has decided whether XR is running.
	_boot.call_deferred()


func _boot() -> void:
	var input := _make_input()
	harpoon.input = input
	menu.input = input
	input.back_pressed.connect(show_menu)
	menu.footer = "Logs: " + logger.get_log_folder()

	var wanted := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--experiment="):
			wanted = arg.get_slice("=", 1)
		elif arg.begins_with("--participant="):
			menu.participant = arg.get_slice("=", 1).to_int()
	for candidate in Experiment.load_all():
		if candidate.get_id() == wanted:
			start_experiment(candidate)
			return
	if not wanted.is_empty():
		push_warning("RiverGame|WARN: no experiment '%s' in %s" % [wanted, Experiment.FOLDER])
	show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if is_instance_valid(logger) and logger.is_running():
			logger.end_session("quit", inventory.items)


## Stops any running experiment (logged as "aborted") and shows the menu.
func show_menu() -> void:
	if menu.visible:
		return
	if logger.is_running():
		logger.end_session("aborted", inventory.items)
	_stop()
	collection.reset(false)
	menu.open(Experiment.load_all())


func start_experiment(p_experiment: Experiment) -> void:
	for problem in p_experiment.problems():
		push_warning("RiverGame|WARN: experiment '%s' %s" % [p_experiment.get_id(), problem])
	_stop()
	menu.close()
	experiment = p_experiment
	_apply_skin(experiment.look)
	harpoon.visible = true

	session_seed = experiment.fixed_seed if experiment.fixed_seed >= 0 else randi()
	_rng.seed = session_seed
	_trials = experiment.build_trials(_rng)
	if _trials.is_empty():
		push_error("RiverGame|ERROR: experiment '%s' has no trials" % experiment.get_id())
		show_menu()
		return
	_trial = -1
	inventory.clear()
	collection.reset(experiment.reward_table != null)
	logger.start_session(experiment, menu.participant_label(), session_seed, _trials)
	_next_trial()


func _process(_delta: float) -> void:
	if _accepting and current_task.time_limit > 0.0 \
			and Time.get_ticks_usec() - _trial_start_usec >= current_task.time_limit * 1_000_000.0:
		_set_accepting(false)
		_finish_trial("timeout", experiment.timeout_text, false)


func _next_trial() -> void:
	_trial += 1
	if _trial >= _trials.size():
		_end_experiment()
		return
	current_task = _trials[_trial]

	# Always drawn, so a fixed-seed task doesn't shift the seeds of later trials.
	var derived_seed := _rng.randi()
	var trial_seed := current_task.fixed_layout_seed if current_task.fixed_layout_seed >= 0 else derived_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = trial_seed

	var objects := spawner.spawn(current_task.get_pools(), rng)
	targets.clear()
	if current_task.get_rule():
		targets = current_task.get_rule().find_targets(objects, current_task)
	if targets.is_empty():
		push_warning("RiverGame|WARN: task '%s' has no correct target in this layout" % current_task.get_id())

	harpoon.candidates = objects
	var preview: RiverObjectConfig = current_task.reference_object if current_task.show_reference_model else null
	task_ui.show_task(current_task.question_text, current_task.get_reference_image(), preview)
	GameAudio.speak(current_task.get_question_audio())

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

	var run := _run
	await harpoon.animation_finished
	if run != _run:
		return
	target.visible = false
	# Independent of the reward table: a right catch plays "reward", a wrong one "wrong".
	GameAudio.play(&"reward" if correct else &"wrong")
	if experiment.reward_table:
		var rewards := experiment.reward_table.rewards_for(target, correct)
		if not rewards.is_empty():
			collection.add(target.config)
			collection.show_success(experiment.success_text, experiment.success_seconds)
		for item in rewards:
			inventory.add(item, rewards[item])
		logger.log_rewards(rewards)

	if correct or not current_task.retry_until_correct:
		var feedback := experiment.correct_text if correct else experiment.wrong_text
		if correct and experiment.show_time_on_correct:
			feedback += "\n%.2f s" % ((time_usec - _trial_start_usec) / 1_000_000.0)
		_finish_trial("correct" if correct else "wrong", feedback, correct)
	else:
		await _show_feedback(experiment.wrong_text, false)
		if run == _run:
			_set_accepting(true)


func _finish_trial(outcome: String, feedback: String, positive: bool) -> void:
	logger.end_trial(outcome)
	var run := _run
	await _show_feedback(feedback, positive)
	if run != _run:
		return
	task_ui.hide_task()
	spawner.clear()
	await get_tree().create_timer(experiment.pause_between_trials).timeout
	if run == _run:
		_next_trial()


func _show_feedback(text: String, positive: bool) -> void:
	if text.is_empty():
		return
	task_ui.show_feedback(text, positive)
	await get_tree().create_timer(experiment.feedback_seconds).timeout
	task_ui.hide_feedback()


func _end_experiment() -> void:
	_set_accepting(false)
	current_task = null
	task_ui.show_task(experiment.end_text)
	logger.end_session("completed", inventory.items)
	menu.mark_done(experiment)
	var run := _run
	await get_tree().create_timer(end_screen_seconds).timeout
	if run == _run:
		show_menu()


## Clears the river and the panels. Pending awaits of the old run are dropped.
func _stop() -> void:
	_run += 1
	GameAudio.stop_voice()
	_set_accepting(false)
	current_task = null
	spawner.clear()
	task_ui.hide_task()
	task_ui.hide_feedback()
	harpoon.visible = false


## XR controller when a headset is running, otherwise mouse / keyboard / gamepad.
func _make_input() -> AimInput:
	if input_override:
		return input_override
	var input: AimInput
	if get_viewport().use_xr:
		var xr := XRAimInput.new()
		xr.controller = aim_controller
		xr.back_controller = menu_controller
		xr.hand_controller = hand_controller
		input = xr
		if menu_controller:
			var help := HelpCard.new()
			help.name = "HelpCard"
			help.controller = menu_controller
			menu_controller.add_child(help)
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


## Swaps the look. Runs between experiments, so it also undoes the previous skin.
func _apply_skin(skin: RiverSkin) -> void:
	spawner.skin = skin
	task_ui.skin = skin
	collection.skin = skin
	harpoon.spear_scene = skin.spear_scene if skin else null
	if _scenery:
		# Removed right away so its Scenery restores the environment before the next one copies its own.
		remove_child(_scenery)
		_scenery.queue_free()
		_scenery = null
	if skin and skin.scenery:
		_scenery = skin.scenery.instantiate()
		_scenery.name = "Scenery"
		add_child(_scenery)
	var has_scenery := _scenery != null
	spawner.set_water_visible(not has_scenery)
	for path in hide_with_scenery:
		var node := get_node_or_null(path)
		if node:
			node.set("visible", not has_scenery)
			node.process_mode = Node.PROCESS_MODE_DISABLED if has_scenery else Node.PROCESS_MODE_INHERIT


func _set_accepting(value: bool) -> void:
	_accepting = value
	harpoon.enabled = value
