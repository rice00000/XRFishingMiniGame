class_name TrialLogger
extends Node
## Writes every run to `log_dir`:
##   sessions.csv          one row per run: who, which experiment, how it went. Start here.
##   trials.csv            one row per trial, all runs appended (load this one file to analyse).
##   runs/<session>.jsonl  everything about one run: setup, every object, every aim ray.
## A session id reads as "<date>_<time>_<participant>_<experiment>", e.g.
## 2026-09-29_14-03-11_P007_fastest_of_five_identical_fish, and appears in all three.
## Times are milliseconds since the trial started, i.e. since the objects and the task
## were shown. Precision is one frame.

@export var enabled := true
@export var log_dir := "user://trial_logs"
@export var print_summary := true

const SESSION_HEADER := [
	"session_id", "participant", "experiment", "title", "started", "ended", "status",
	"trials_done", "trials_planned", "n_correct", "accuracy", "mean_response_ms",
	"seed", "look", "platform", "detail_file",
]
const TRIAL_HEADER := [
	"session_id", "participant", "experiment", "trial", "task_id", "reference", "rule",
	"seed", "outcome", "correct", "response_ms", "attempts", "misses",
	"selected", "selected_swim_speed_m_per_s", "selected_spin_speed_deg_per_s",
	"target", "target_swim_speed_m_per_s", "target_spin_speed_deg_per_s",
	"spawned", "rewards",
]

var session_id := ""
var session_seed := 0

var _experiment: Experiment
var _participant := ""
var _platform := ""
var _started := ""
var _planned := 0
var _done := 0
var _correct := 0
var _response_sum := 0.0
var _responses := 0
var _json: FileAccess
var _trials_csv: FileAccess
var _trial := {}
var _start_usec := 0


func is_running() -> bool:
	return _experiment != null


func get_log_folder() -> String:
	return ProjectSettings.globalize_path(log_dir)


func start_session(experiment: Experiment, participant: String, p_session_seed: int, trials: Array[RiverTask]) -> void:
	_experiment = experiment
	_participant = participant
	session_seed = p_session_seed
	_platform = "%s %s" % [OS.get_name(), "xr" if get_viewport().use_xr else "desktop"]
	_started = Time.get_datetime_string_from_system()
	_planned = trials.size()
	_done = 0
	_correct = 0
	_response_sum = 0.0
	_responses = 0
	session_id = "%s_%s_%s" % [_started.replace(":", "-").replace("T", "_"), participant, experiment.get_id()]
	if enabled:
		DirAccess.make_dir_recursive_absolute(log_dir.path_join("runs"))
		_json = FileAccess.open(_detail_path(), FileAccess.WRITE)
		_trials_csv = _open_csv("trials.csv", TRIAL_HEADER)
		if _json == null or _trials_csv == null:
			push_error("TrialLogger|ERROR: cannot write to %s" % get_log_folder())
		else:
			print("TrialLogger|INFO: logging %s to %s" % [session_id, get_log_folder()])

	var task_setup := []
	for task in experiment.tasks:
		if task:
			task_setup.append(_describe_task(task))
	_write({
		"type": "session_start",
		"session_id": session_id,
		"participant": participant,
		"experiment": experiment.get_id(),
		"title": experiment.get_title(),
		"description": experiment.description,
		"experiment_file": experiment.resource_path,
		"look": experiment.look.resource_path if experiment.look else "",
		"seed": session_seed,
		"shuffle_trial_order": experiment.shuffle_trial_order,
		"tasks": task_setup,
		"trial_order": trials.map(func(t: RiverTask) -> String: return _trial_label(t)),
		"time": _started,
		"engine": Engine.get_version_info().string,
		"platform": _platform,
	})


func begin_trial(trial: int, task: RiverTask, trial_seed: int, objects: Array[RiverObject], targets: Array[RiverObject], start_usec: int) -> void:
	_start_usec = start_usec
	var spawned := []
	for obj in objects:
		spawned.append(obj.to_log_dict())
	_trial = {
		"type": "trial",
		"session_id": session_id,
		"trial": trial,
		"task_id": String(task.get_id()),
		"question_text": task.question_text,
		"reference": String(task.reference_object.get_id()) if task.reference_object else "",
		"rule": task.describe_rule(),
		"seed": trial_seed,
		"spawned": spawned,
		"correct_targets": targets.map(_ref),
		"selections": [],
		"misses": [],
		"selected": null,
		"response_ms": null,
		"first_response_ms": null,
		"correct": false,
		"outcome": "",
		"rewards": {},
	}


## Confirm with nothing under the reticle.
func log_miss(time_usec: int, aim_origin: Vector3, aim_direction: Vector3) -> void:
	_trial.misses.append({
		"t_ms": _ms(time_usec),
		"aim_origin": RiverObject.vec_to_array(aim_origin),
		"aim_direction": RiverObject.vec_to_array(aim_direction),
	})


## Confirm with an object selected. The latest selection is the trial's answer.
func log_selection(obj: RiverObject, correct: bool, time_usec: int, aim_origin: Vector3, aim_direction: Vector3) -> void:
	var entry := _ref(obj)
	entry.merge({
		"t_ms": _ms(time_usec),
		"correct": correct,
		"object_position": RiverObject.vec_to_array(obj.global_position),
		"aim_origin": RiverObject.vec_to_array(aim_origin),
		"aim_direction": RiverObject.vec_to_array(aim_direction),
	})
	_trial.selections.append(entry)
	_trial.selected = _ref(obj)
	_trial.response_ms = entry.t_ms
	_trial.correct = correct
	if _trial.first_response_ms == null:
		_trial.first_response_ms = entry.t_ms


func log_rewards(rewards: Dictionary) -> void:
	for item in rewards:
		_trial.rewards[String(item)] = _trial.rewards.get(String(item), 0) + rewards[item]


## outcome: "correct", "wrong" or "timeout".
func end_trial(outcome: String) -> void:
	_trial.outcome = outcome
	_write(_trial)
	_done += 1
	if _trial.correct:
		_correct += 1
	if _trial.response_ms != null:
		_response_sum += _trial.response_ms
		_responses += 1

	var selected: Variant = _trial.selected
	var target: Variant = _trial.correct_targets[0] if not _trial.correct_targets.is_empty() else null
	var rewards := PackedStringArray()
	for item in _trial.rewards:
		rewards.append("%s:%d" % [item, _trial.rewards[item]])
	var row := [
		session_id, _participant, _experiment.get_id(), _trial.trial, _trial.task_id, _trial.reference,
		_trial.rule, _trial.seed, outcome, _trial.correct,
		_trial.response_ms if _trial.response_ms != null else "", _trial.selections.size(), _trial.misses.size(),
		selected.id if selected else "", selected.swim_speed_m_per_s if selected else "", selected.spin_speed_deg_per_s if selected else "",
		"|".join(_trial.correct_targets.map(func(o): return o.id)),
		target.swim_speed_m_per_s if target else "", target.spin_speed_deg_per_s if target else "",
		"|".join(_trial.spawned.map(func(o): return o.id)), "|".join(rewards),
	]
	if _trials_csv:
		_trials_csv.store_csv_line(PackedStringArray(row.map(func(v): return str(v))))
		_trials_csv.flush()

	if print_summary:
		print("TrialLogger|INFO: trial %d %s rule=%s selected=%s rt=%sms misses=%d" % [
			_trial.trial, outcome, _trial.rule, row[13], row[10], _trial.misses.size()])


## status: "completed", "aborted" (back to the menu) or "quit" (app closed).
func end_session(status: String, inventory: Dictionary) -> void:
	if not is_running():
		return
	var ended := Time.get_datetime_string_from_system()
	var items := {}
	for item in inventory:
		items[String(item)] = inventory[item]
	_write({"type": "session_end", "session_id": session_id, "status": status, "inventory": items, "time": ended})

	var sessions := _open_csv("sessions.csv", SESSION_HEADER) if enabled else null
	if sessions:
		sessions.store_csv_line(PackedStringArray([
			session_id, _participant, _experiment.get_id(), _experiment.get_title(), _started, ended, status,
			_done, _planned, _correct,
			snappedf(_correct / float(_done), 0.001) if _done > 0 else "",
			snappedf(_response_sum / _responses, 0.1) if _responses > 0 else "",
			session_seed, _experiment.look.resource_path.get_file().get_basename() if _experiment.look else "none",
			_platform, _detail_path().trim_prefix(log_dir + "/"),
		].map(func(v): return str(v))))
	print("TrialLogger|INFO: %s %s, %d/%d trials, %d correct" % [session_id, status, _done, _planned, _correct])
	_experiment = null
	_json = null
	_trials_csv = null


func _detail_path() -> String:
	return log_dir.path_join("runs").path_join(session_id + ".jsonl")


## Opens a CSV for appending. A file with a different header (older version) is
## renamed out of the way so every file keeps a single consistent header.
func _open_csv(file_name: String, header: Array) -> FileAccess:
	var path := log_dir.path_join(file_name)
	var header_line := ",".join(header)
	if FileAccess.file_exists(path):
		var existing := FileAccess.open(path, FileAccess.READ)
		var first_line := existing.get_line().strip_edges() if existing else ""
		existing = null
		if first_line == header_line:
			var file := FileAccess.open(path, FileAccess.READ_WRITE)
			if file:
				file.seek_end()
			return file
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		DirAccess.rename_absolute(path, path.get_basename() + "_old_%s.csv" % stamp)
	var created := FileAccess.open(path, FileAccess.WRITE)
	if created:
		created.store_csv_line(PackedStringArray(header))
	return created


func _write(record: Dictionary) -> void:
	if _json:
		_json.store_line(JSON.stringify(record))
		_json.flush()


func _ms(time_usec: int) -> float:
	return snappedf((time_usec - _start_usec) / 1000.0, 0.1)


static func _trial_label(task: RiverTask) -> String:
	var label := String(task.get_id())
	if task.reference_object:
		label += ":" + String(task.reference_object.get_id())
	return label


static func _describe_task(task: RiverTask) -> Dictionary:
	var pools := []
	for pool in task.get_pools():
		pools.append({
			"id": String(pool.get_id()),
			"count": pool.count,
			"unique": pool.unique,
			"objects": pool.get_objects().map(func(c: RiverObjectConfig) -> String: return String(c.get_id())),
		})
	return {
		"id": String(task.get_id()),
		"question_text": task.question_text,
		"rule": task.describe_rule(),
		"repeat_times": task.repeat_times,
		"each_object_as_reference": task.each_object_as_reference,
		"reference": String(task.reference_object.get_id()) if task.reference_object else "",
		"pools": pools,
		"time_limit": task.time_limit,
		"retry_until_correct": task.retry_until_correct,
	}


## Compact object reference for selections and targets (id + the values usually analysed).
static func _ref(obj: RiverObject) -> Dictionary:
	return {
		"index": obj.index,
		"id": String(obj.config.get_id()),
		"pool": String(obj.pool_id),
		"swim_speed_m_per_s": obj.config.swim_speed_m_per_s,
		"spin_speed_deg_per_s": obj.config.spin_speed_deg_per_s,
	}
