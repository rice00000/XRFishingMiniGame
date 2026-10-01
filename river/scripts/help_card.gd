class_name HelpCard
extends Node3D
## VR controls card on the left hand. A small "Y · Help" tag always floats on the
## controller; pressing Y opens a card above the hand that turns to face the player
## (lift the hand closer to read it bigger). Press Y again to close it.
## RiverGame adds it to the menu controller when a headset is running.

## Controller the card sits on and whose button toggles it.
@export var controller: XRController3D
@export var toggle_action := &"by_button"
## Card centre relative to the hand, in metres (up, towards the player).
@export var card_offset := Vector3(0.0, 0.2, 0.0)

const KEYS := "Aim\nShoot\nThrow\nMenu\nStart\nHelp"
const TEXT := "point the right controller: the yellow ring\n" \
		+ "right trigger: hits what is in the ring\n" \
		+ "hold right grip: swing + let go, or just stab\n" \
		+ "left menu button: stop, back to the list\n" \
		+ "in the list: point + trigger; < > = participant\n" \
		+ "Y (left hand): open / close this card"
const CARD_SIZE := Vector2(0.52, 0.25)
const PIXEL := 0.0006 ## metres per font pixel
const KEY_WIDTH := 0.08

var _tag: Label3D
var _card: Node3D


func _ready() -> void:
	_tag = _label("Y · Help", 36, BeachStyle.SUN)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0.0, 0.06, 0.02)
	add_child(_tag)

	_card = Node3D.new()
	_card.name = "Card"
	_card.top_level = true
	_card.visible = false
	add_child(_card)
	_card.add_child(BeachStyle.make_panel(CARD_SIZE, 0.03, BeachStyle.DEEP, BeachStyle.SAND, 0.004))
	var title := _label("CONTROLS", 40, BeachStyle.SUN)
	title.position = Vector3(0.0, CARD_SIZE.y * 0.5 - 0.025, 0.002)
	_card.add_child(title)
	var left := -CARD_SIZE.x * 0.5 + 0.02
	_card.add_child(_column(KEYS, BeachStyle.SUN, left, KEY_WIDTH))
	_card.add_child(_column(TEXT, BeachStyle.CREAM, left + KEY_WIDTH, CARD_SIZE.x - 0.04 - KEY_WIDTH))

	if controller:
		controller.button_pressed.connect(_on_button_pressed)


func _process(_delta: float) -> void:
	if not _card.visible:
		return
	# Float above the hand and face the eyes, without rolling.
	var center := global_position + card_offset
	var eye := get_viewport().get_camera_3d()
	var to_eye := (eye.global_position - center) if eye else Vector3.BACK
	if to_eye.length_squared() < 0.0001 or absf(to_eye.normalized().y) > 0.98:
		return
	_card.global_transform = Transform3D(Basis.looking_at(-to_eye, Vector3.UP), center)


func _on_button_pressed(action: String) -> void:
	if action == toggle_action:
		_card.visible = not _card.visible


func _label(value: String, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = size
	label.pixel_size = PIXEL
	label.outline_size = 8
	label.double_sided = false
	BeachStyle.style_label(label, color)
	return label


## Left-aligned text in a box `width` metres wide starting at `left`.
func _column(value: String, color: Color, left: float, width: float) -> Label3D:
	var label := _label(value, 28, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = width / PIXEL
	label.position = Vector3(left, -0.014, 0.002) # left-aligned text starts at the origin
	return label
