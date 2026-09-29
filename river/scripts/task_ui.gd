class_name TaskUI
extends Node3D
## World-space task panel: text, optional reference image or model, feedback and
## inventory. Pure presentation; it never decides what is correct.

## Background, hidden together with the task between trials.
@export var panel: Node3D
@export var task_label: Label3D
@export var reference_image: Sprite3D
@export var reference_model: Node3D
@export var feedback_label: Label3D
@export var inventory_label: Label3D
## Must match the Panel mesh width; used to lay out text next to a reference.
@export var panel_width := 3.2
## Height of the reference image / model in metres.
@export var reference_height := 0.75
@export var positive_color := Color(0.35, 1.0, 0.35)
@export var negative_color := Color(1.0, 0.6, 0.15)

## Optional look for the reference model. Set by RiverGame.
var skin: RiverSkin


func _ready() -> void:
	hide_task()
	hide_feedback()


func show_task(text: String, image: Texture2D = null, model: RiverObjectConfig = null) -> void:
	visible = true
	panel.visible = true
	task_label.text = text

	reference_image.texture = image
	reference_image.visible = image != null
	if image:
		reference_image.pixel_size = reference_height / image.get_height()

	for child in reference_model.get_children():
		child.queue_free()
	if model:
		# Shown still (no spin or drift) so the preview doesn't hint at motion rules.
		var preview := RiverObject.build_visual(model, skin.scene_for(model) if skin else null)
		preview.basis = Basis.from_euler(model.start_tilt_degrees * (PI / 180.0)) * (reference_height / maxf(model.size, 0.01) * 0.8)
		reference_model.add_child(preview)

	# Text uses the whole panel unless a reference sits on its right.
	var margin := 0.15
	var reference_space := reference_height + margin if image or model else 0.0
	var text_width := panel_width - 2.0 * margin - reference_space
	task_label.width = text_width / task_label.pixel_size
	task_label.position.x = -panel_width * 0.5 + margin + text_width * 0.5
	var reference_x := panel_width * 0.5 - margin - reference_height * 0.5
	reference_image.position.x = reference_x
	reference_model.position.x = reference_x


func hide_task() -> void:
	panel.visible = false
	task_label.text = ""
	reference_image.visible = false
	for child in reference_model.get_children():
		child.queue_free()


func show_feedback(text: String, positive: bool) -> void:
	feedback_label.text = text
	feedback_label.modulate = positive_color if positive else negative_color
	feedback_label.visible = not text.is_empty()


func hide_feedback() -> void:
	feedback_label.visible = false


func show_inventory(items: Dictionary) -> void:
	var lines := PackedStringArray()
	for item in items:
		lines.append("%s x %d" % [item, items[item]])
	inventory_label.text = "\n".join(lines)
