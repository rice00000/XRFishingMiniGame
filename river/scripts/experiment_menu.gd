class_name ExperimentMenu
extends Node3D
## World-space experiment picker, driven by the same aim + confirm input as the
## harpoon: point at a row and fire. Lists Experiment.load_all(), plus a participant
## number that goes into every log. Built in code; place the node where the panel
## should float (it faces +Z).

signal chosen(experiment: Experiment)

const SETTINGS_PATH := "user://river_settings.cfg"

@export var panel_width := 3.2
@export var row_height := 0.22
@export var rows_per_page := 6
@export var font_size := 48
@export var small_font_size := 30
@export var text_color := Color.WHITE
## Matches the harpoon reticle.
@export var hover_color := Color(1.0, 0.9, 0.0)
@export var button_color := Color(0.18, 0.18, 0.18)
@export var panel_color := Color.BLACK
@export var warning_color := Color(1.0, 0.6, 0.15)

## Where aim and confirm come from. Set by RiverGame.
var input: AimInput:
	set(value):
		if input and input.confirm_pressed.is_connected(_on_confirm):
			input.confirm_pressed.disconnect(_on_confirm)
		input = value
		if input:
			input.confirm_pressed.connect(_on_confirm)
## Written to the logs. Kept between app runs.
var participant := 1:
	set(value):
		participant = maxi(value, 1)
		var settings := ConfigFile.new()
		settings.load(SETTINGS_PATH)
		settings.set_value("menu", "participant", participant)
		settings.save(SETTINGS_PATH)
## Shown under the list, e.g. where the logs go.
var footer := ""

var _experiments: Array[Experiment] = []
var _done := {} # "participant/experiment id" -> true
var _page := 0
var _buttons: Array[Dictionary] = [] # {rect: Rect2, bg: MeshInstance3D, label: Label3D, action: Callable, experiment}
var _hovered := -1
var _content: Node3D
var _description: Label3D
var _cursor: MeshInstance3D
var _beam: MeshInstance3D


func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		participant = settings.get_value("menu", "participant", 1)
	_cursor = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.025
	dot.height = 0.05
	dot.material = _material(hover_color, true)
	_cursor.mesh = dot
	_beam = MeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(0.006, 0.006, 1.0)
	line.material = _material(Color(hover_color, 0.7), true)
	_beam.mesh = line
	for node: MeshInstance3D in [_cursor, _beam]:
		node.top_level = true
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	visible = false


func open(experiments: Array[Experiment]) -> void:
	_experiments = experiments
	_page = clampi(_page, 0, _page_count() - 1)
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	_cursor.visible = false
	_beam.visible = false


func participant_label() -> String:
	return "P%03d" % participant


func mark_done(experiment: Experiment) -> void:
	_done["%d/%s" % [participant, experiment.get_id()]] = true


func _process(_delta: float) -> void:
	if not visible:
		return
	var ray := input.get_aim_ray() if input else []
	var hit: Variant = null
	if not ray.is_empty():
		hit = Plane(global_basis.z, global_position).intersects_ray(ray[0], ray[1])
	_cursor.visible = hit != null
	_beam.visible = hit != null and input.wants_beam()
	if hit == null:
		_set_hovered(-1)
		return

	_cursor.global_position = hit
	if _beam.visible:
		var beam_vector: Vector3 = hit - ray[0]
		_beam.global_transform = Transform3D(
			Basis.looking_at(beam_vector.normalized(), Vector3.UP).scaled_local(Vector3(1, 1, beam_vector.length())),
			ray[0] + beam_vector * 0.5)
	var local := _content.to_local(hit)
	var point := Vector2(local.x, local.y)
	for i in _buttons.size():
		if _buttons[i].rect.has_point(point):
			_set_hovered(i)
			return
	_set_hovered(-1)


func _on_confirm() -> void:
	if not visible or _hovered < 0:
		return
	input.pulse()
	_buttons[_hovered].action.call()


func _rebuild() -> void:
	if _content:
		remove_child(_content)
		_content.queue_free()
	_content = Node3D.new()
	add_child(_content)
	_buttons.clear()
	_hovered = -1

	# Laid out top-down from y = 0, then centred on this node.
	var margin := 0.12
	var gap := row_height * 0.25
	var inner := panel_width - 2.0 * margin
	var left := -inner * 0.5
	var arrow := row_height * 1.6
	var y := -margin

	_add_label("Choose an experiment", Vector2(0, y - row_height * 0.5), font_size)
	y -= row_height + gap

	# Participant: [<] P007 [>]
	_add_button(Rect2(left, y - row_height, arrow, row_height), "<", func() -> void: _change_participant(-1))
	_add_button(Rect2(-left - arrow, y - row_height, arrow, row_height), ">", func() -> void: _change_participant(1))
	_add_label("Participant  " + participant_label(), Vector2(0, y - row_height * 0.5), font_size)
	y -= row_height + gap * 2.0

	var list_top := y
	var first := _page * rows_per_page
	for i in range(first, mini(first + rows_per_page, _experiments.size())):
		var experiment := _experiments[i]
		var text := experiment.get_title()
		if _done.has("%d/%s" % [participant, experiment.get_id()]):
			text += "  (done)"
		var index := _add_button(Rect2(left, y - row_height, inner, row_height), text,
				func() -> void: chosen.emit.call_deferred(experiment))
		_buttons[index].experiment = experiment
		y -= row_height + gap * 0.5
	if _experiments.is_empty():
		_add_label("No experiments in %s" % Experiment.FOLDER, Vector2(0, y - row_height * 0.5), small_font_size)
	# Fixed height, so the panel doesn't jump between pages.
	y = list_top - (row_height + gap * 0.5) * rows_per_page - gap

	var pages := _page_count()
	if pages > 1:
		_add_button(Rect2(left, y - row_height, arrow, row_height), "<", func() -> void: _change_page(-1))
		_add_button(Rect2(-left - arrow, y - row_height, arrow, row_height), ">", func() -> void: _change_page(1))
		_add_label("Page %d / %d" % [_page + 1, pages], Vector2(0, y - row_height * 0.5), small_font_size)
		y -= row_height + gap

	var description_height := row_height * 1.8
	_description = _add_label("", Vector2(0, y - description_height * 0.5), small_font_size)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.width = inner / _description.pixel_size
	y -= description_height + gap
	var footer_label := _add_label(footer, Vector2(0, y - row_height * 0.25), 22)
	footer_label.modulate = Color(text_color, 0.6)
	y -= row_height * 0.5 + margin

	_add_quad(Rect2(-panel_width * 0.5, y, panel_width, -y), panel_color, 0.0)
	_content.position.y = -y * 0.5
	_show_description(null)


func _change_participant(step: int) -> void:
	participant += step
	_rebuild()


func _change_page(step: int) -> void:
	_page = wrapi(_page + step, 0, _page_count())
	_rebuild()


func _page_count() -> int:
	return maxi(ceili(_experiments.size() / float(rows_per_page)), 1)


func _set_hovered(index: int) -> void:
	if index == _hovered:
		return
	if _hovered >= 0:
		_style_button(_buttons[_hovered], false)
	_hovered = index
	if _hovered >= 0:
		_style_button(_buttons[_hovered], true)
	_show_description(_buttons[_hovered].get("experiment") if _hovered >= 0 else null)


func _show_description(experiment: Experiment) -> void:
	if experiment == null:
		_description.text = "Aim at an experiment and fire.\nMenu button (Esc on PC) comes back here and stops the run."
		_description.modulate = Color(text_color, 0.8)
		return
	var problems := experiment.problems()
	var trials := experiment.build_trials(RandomNumberGenerator.new()).size()
	var text := "%s\n%d trials%s" % [experiment.description, trials, ", shuffled" if experiment.shuffle_trial_order else ""]
	if not problems.is_empty():
		text += "\nCheck setup: " + problems[0]
	_description.text = text.strip_edges()
	_description.modulate = warning_color if not problems.is_empty() else text_color


func _style_button(button: Dictionary, hovered: bool) -> void:
	(button.bg.mesh.material as StandardMaterial3D).albedo_color = hover_color if hovered else button_color
	button.label.modulate = Color.BLACK if hovered else text_color
	button.label.outline_modulate = Color(0, 0, 0, 0) if hovered else Color.BLACK


func _add_button(rect: Rect2, text: String, action: Callable) -> int:
	var button := {
		"rect": rect,
		"bg": _add_quad(rect, button_color, 0.005),
		"label": _add_label(text, rect.get_center(), _fitting_font_size(text, rect.size.x - row_height * 0.4)),
		"action": action,
	}
	_buttons.append(button)
	_style_button(button, false)
	return _buttons.size() - 1


## font_size, made smaller if `text` would be wider than `width` metres.
func _fitting_font_size(text: String, width: float) -> int:
	var text_width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.004
	return font_size if text_width <= width else maxi(int(font_size * width / text_width), small_font_size)


## `rect` is in the panel plane, y up.
func _add_quad(rect: Rect2, color: Color, z: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = rect.size
	quad.material = _material(color, false)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(rect.get_center().x, rect.get_center().y, z)
	_content.add_child(mesh)
	return mesh


func _add_label(text: String, center: Vector2, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.004
	label.font_size = size
	label.outline_size = size / 4
	label.modulate = text_color
	label.position = Vector3(center.x, center.y, 0.012)
	label.render_priority = 10
	label.outline_render_priority = 9
	_content.add_child(label)
	return label


static func _material(color: Color, overlay: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if overlay:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 20
	return mat
