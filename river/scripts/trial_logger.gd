class_name TrialLogger
extends Node
## Writes one JSON line per trial (full detail) and one CSV row per trial (quick
## analysis) to `log_dir`. Times are milliseconds since the trial started, i.e. since
## the objects and the task were shown. Precision is one frame.

@export var enabled := true
@export var log_dir := "user://trial_logs"
@export var print_summary := true

const CSV_HEADER := [
	"session_id", "trial", "task_id", "rule", "seed", "spawned", "correct_targets",
	"selected", "selected_pool", "response_ms", "correct", "outcome",
	"attempts", "misses", "rewards",
]

var session_id := ""
var session_seed := 0

var _json: FileAccess
var _csv: FileAccess
var _trial := {}
var _start_usec := 0


func start_session(p_session_seed: int, session: RiverSession) -> void:
	session_seed = p_session_seed
	session_id = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	if enabled:
		DirAccess.make_dir_recursive_absolute(log_dir)
		var base := log_dir.path_join("session_" + session_id)
		_json = FileAccess.open(base + ".jsonl", FileAccess.WRITE)
		_csv = FileAccess.open(base + ".csv", FileAccess.WRITE)
		if _json == null or _csv == null:
			push_error("TrialLogger|ERROR: cannot write to %s" % ProjectSettings.globalize_path(log_dir))
		else:
			_csv.store_csv_line(PackedStringArray(CSV_HEADER))
			print("TrialLogger|INFO: logging to %s.jsonl/.csv" % ProjectSettings.globalize_path(base))
	_write({
		"type": "session_start",
		"session_id": session_id,
		"seed": session_seed,
		"session": session.resource_path,
		"task_count": session.tasks.size(),
		"shuffle_tasks": session.shuffle_tasks,
		"time": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info().string,
		"xr": get_viewport().use_xr,
	})


func begin_trial(trial: int, task: RiverTask, trial_seed: int, objects: Array[RiverObject], targets: Array[RiverObject], start_usec: int) -> void:
	_start_usec = start_usec
	var spawned := []
	for obj in objects:
		spawned.append(obj.to_log_dict())
	_trial = {
		"type": "trial",
		"session_id": session_id,
		"session_seed": session_seed,
		"trial": trial,
		"task_id": String(task.get_id()),
		"task_text": task.text,
		"rule": task.rule.describe() if task.rule else "none",
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

	var selected: Variant = _trial.selected
	var rewards := PackedStringArray()
	for item in _trial.rewards:
		rewards.append("%s:%d" % [item, _trial.rewards[item]])
	var row := [
		session_id, _trial.trial, _trial.task_id, _trial.rule, _trial.seed,
		"|".join(_trial.spawned.map(func(o): return "%s#%d" % [o.id, o.index])),
		"|".join(_trial.correct_targets.map(func(o): return "%s#%d" % [o.id, o.index])),
		"%s#%d" % [selected.id, selected.index] if selected else "",
		selected.pool if selected else "",
		_trial.response_ms if _trial.response_ms != null else "",
		_trial.correct, outcome, _trial.selections.size(), _trial.misses.size(), "|".join(rewards),
	]
	if _csv:
		_csv.store_csv_line(PackedStringArray(row.map(func(v): return str(v))))
		_csv.flush()

	if print_summary:
		print("TrialLogger|INFO: trial %d %s rule=%s selected=%s rt=%sms misses=%d" % [
			_trial.trial, outcome, _trial.rule, row[7], row[9], _trial.misses.size()])


func end_session(inventory: Dictionary) -> void:
	var items := {}
	for item in inventory:
		items[String(item)] = inventory[item]
	_write({"type": "session_end", "session_id": session_id, "inventory": items, "time": Time.get_datetime_string_from_system()})
	_json = null
	_csv = null


func _write(record: Dictionary) -> void:
	if _json:
		_json.store_line(JSON.stringify(record))
		_json.flush()


func _ms(time_usec: int) -> float:
	return snappedf((time_usec - _start_usec) / 1000.0, 0.1)


static func _ref(obj: RiverObject) -> Dictionary:
	return {"index": obj.index, "id": String(obj.config.get_id()), "pool": String(obj.pool_id)}
