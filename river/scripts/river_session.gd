class_name RiverSession
extends Resource
## A run of tasks plus the settings they share.

@export var tasks: Array[RiverTask] = []
@export var reward_table: RewardTable
## Seed for the whole session. -1 = new random seed each run.
## The seed is always logged, so any run can be replayed by entering it here.
@export var fixed_seed := -1
@export var shuffle_tasks := false

@export_group("Feedback")
## Empty text = show nothing.
@export var correct_text := "Great catch!"
@export var wrong_text := "Not that one"
@export var timeout_text := ""
@export var end_text := "All done!"
@export var feedback_seconds := 1.5
@export var pause_between_trials := 1.0
