class_name CollectionBoard
extends Node3D
## World-space board of everything the player has collected this run: one card per kind
## of caught object (its 2D picture if it has one, else its model), with a "x N" count.
## Also shows a short "Success!" pill when something is added. Built in code; the node
## is the top centre of the board, which grows downward as cards are added. Pure
## presentation: RiverGame adds items when a catch grants a reward.

@export var title := "Collection"
@export var empty_text := "Catch something!"
@export var columns := 3
## Cards beyond this are counted under "+N more" instead of drawn.
@export var max_cards := 9
@export var card_size := Vector2(0.44, 0.52)
@export var gap := 0.05
@export var font_size := 40
@export var count_font_size := 64

## Optional look for the card models. Set by RiverGame.
var skin: RiverSkin

var _keys: Array[StringName] = []
var _cards := {} # key -> {root: Node3D, count: Label3D, total: int}
var _overflow := 0
var _enabled := false
var _content: Node3D
var _toast: Node3D
var _toast_tween: Tween


func _ready() -> void:
	_rebuild()


## Clears the board. `enabled` = false hides it (an experiment without rewards).
func reset(enabled: bool) -> void:
	_enabled = enabled
	_keys.clear()
	_cards.clear()
	_overflow = 0
	hide_success()
	_rebuild()


## Adds `quantity` of the object `config` was made from, e.g. every fish_0.3 counts as "fish".
func add(config: RiverObjectConfig, quantity := 1) -> void:
	if not _enabled or config == null:
		return
	var key := config.variant_of if config.variant_of != &"" else config.get_id()
	if _cards.has(key):
		_cards[key].total += quantity
		_cards[key].count.text = "x %d" % _cards[key].total
		_pop(_cards[key].root)
		return
	if _keys.size() >= max_cards:
		_overflow += quantity
		_rebuild()
		return
	_keys.append(key)
	_cards[key] = {"config": config, "total": quantity}
	_rebuild()
	_pop(_cards[key].root)


## Shows `text` in a pill above the board for `seconds`. Empty text shows nothing.
func show_success(text: String, seconds := 2.0) -> void:
	hide_success()
	if text.is_empty() or not _enabled:
		return
	var label := _make_label(text, Vector3(0, 0, 0.02), 64, BeachStyle.INK)
	label.outline_size = 0
	label.render_priority = 13
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * label.pixel_size + 0.4
	_toast = Node3D.new()
	_toast.add_child(BeachStyle.make_panel(Vector2(width, 0.22), 0.11, BeachStyle.MINT, Color(BeachStyle.CREAM, 1.0), 0.012, 12))
	_toast.add_child(label)
	_toast.position = Vector3(0, 0.2, 0.05)
	_toast.scale = Vector3.ONE * 0.01
	add_child(_toast)
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(maxf(seconds - 0.45, 0.0))
	_toast_tween.tween_property(_toast, "scale", Vector3.ONE * 0.01, 0.2)
	_toast_tween.tween_callback(hide_success)


func hide_success() -> void:
	if _toast_tween:
		_toast_tween.kill()
		_toast_tween = null
	if _toast:
		remove_child(_toast)
		_toast.queue_free()
		_toast = null


func _rebuild() -> void:
	if _content:
		remove_child(_content)
		_content.queue_free()
		_content = null
	visible = _enabled
	if not _enabled:
		return
	_content = Node3D.new()
	add_child(_content)

	var margin := 0.07
	var header := 0.16
	var count := _keys.size()
	var rows := ceili(count / float(columns))
	var width := columns * card_size.x + (columns - 1) * gap + 2.0 * margin
	var body := rows * card_size.y + maxi(rows - 1, 0) * gap if rows > 0 else 0.12
	var footer := 0.12 if _overflow > 0 else 0.0
	var height := margin + header + body + footer + margin

	var background := BeachStyle.make_panel(Vector2(width, height), 0.08, BeachStyle.DEEP, BeachStyle.SAND, 0.012, BeachStyle.BACK)
	background.position = Vector3(0, -height * 0.5, 0)
	_content.add_child(background)
	_content.add_child(_make_label(title.to_upper(), Vector3(0, -margin - header * 0.5, 0.012), font_size, Color(BeachStyle.SAND, 1.0)))

	var top := -margin - header
	if count == 0:
		_content.add_child(_make_label(empty_text, Vector3(0, top - body * 0.5, 0.012), font_size - 8, Color(BeachStyle.CREAM, 0.7)))
	for i in count:
		var cell := Vector2(i % columns, floori(i / float(columns)))
		var center := Vector3(
			-width * 0.5 + margin + card_size.x * 0.5 + cell.x * (card_size.x + gap),
			top - card_size.y * 0.5 - cell.y * (card_size.y + gap), 0.01)
		_cards[_keys[i]].root = _make_card(_cards[_keys[i]], center)
	if _overflow > 0:
		_content.add_child(_make_label("+%d more" % _overflow, Vector3(0, -height + margin + footer * 0.5, 0.012), font_size - 8, Color(BeachStyle.CREAM, 0.8)))


func _make_card(entry: Dictionary, center: Vector3) -> Node3D:
	var config: RiverObjectConfig = entry.config
	var card := Node3D.new()
	card.position = center
	_content.add_child(card)
	card.add_child(BeachStyle.make_panel(card_size, 0.05, BeachStyle.CARD, Color(BeachStyle.SAND, 0.0), 0.012, BeachStyle.FRONT))

	var picture_height := card_size.y * 0.66
	var holder := Node3D.new()
	holder.position = Vector3(0, card_size.y * 0.5 - picture_height * 0.5 - 0.035, 0.025)
	card.add_child(holder)
	if config.picture:
		var sprite := Sprite3D.new()
		sprite.texture = config.picture
		sprite.shaded = false
		sprite.render_priority = 12
		sprite.pixel_size = minf(picture_height / config.picture.get_height(), (card_size.x - 0.06) / config.picture.get_width())
		holder.add_child(sprite)
	else:
		# Shown still, like the task panel's reference model.
		var visual := RiverObject.build_visual(config, skin.scene_for(config) if skin else null)
		visual.basis = Basis.from_euler(config.start_tilt_degrees * (PI / 180.0)) * (minf(picture_height, card_size.x - 0.08) / maxf(config.size, 0.01))
		holder.add_child(visual)

	var count := _make_label("x %d" % entry.total, Vector3(0, -card_size.y * 0.5 + 0.06, 0.02), count_font_size, BeachStyle.CREAM)
	card.add_child(count)
	entry.count = count
	return card


func _make_label(text: String, position: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.0032
	label.font_size = size
	label.outline_size = size / 7
	label.position = position
	BeachStyle.style_label(label, color)
	return label


func _pop(card: Node3D) -> void:
	card.scale = Vector3.ONE * 0.6
	card.create_tween().tween_property(card, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
