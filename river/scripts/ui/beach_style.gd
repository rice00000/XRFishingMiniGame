class_name BeachStyle
extends RefCounted
## The look shared by every UI panel (task panel, menu, collection board): deep sea
## panels with a sand edge, cream text, sun-yellow highlights. Kept dark and high
## contrast on purpose, because the players have low vision.

const DEEP := Color(0.05, 0.16, 0.22, 0.96) ## panel background
const CARD := Color(0.10, 0.30, 0.36) ## buttons and cards on a panel
const SAND := Color(0.95, 0.85, 0.66) ## panel edge
const CREAM := Color(1.0, 0.97, 0.90) ## text
const SUN := Color(1.0, 0.9, 0.0) ## hover, same as the harpoon reticle
const INK := Color(0.02, 0.08, 0.12) ## text on SUN, label outlines
const MINT := Color(0.45, 1.0, 0.75) ## positive
const CORAL := Color(1.0, 0.55, 0.42) ## negative

## Draw order of transparent UI. Above 0 so the scenery's water (priority 0) can't veil a
## panel, below the labels (10) so text stays on top.
const BACK := 4 ## panel backgrounds
const FRONT := 5 ## buttons and cards on a panel

const PANEL_SHADER := preload("res://river/scripts/ui/ui_panel.gdshader")


## Material for a rounded rectangle of `size` metres.
static func panel_material(size: Vector2, radius: float, fill: Color, border := Color(SAND, 0.0),
		border_width := 0.012, priority := BACK) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PANEL_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("radius", minf(radius, minf(size.x, size.y) * 0.5))
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("border", border)
	mat.set_shader_parameter("border_width", border_width)
	return mat


## A centred rounded quad.
static func make_panel(size: Vector2, radius: float, fill: Color, border := Color(SAND, 0.0),
		border_width := 0.012, priority := BACK) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = panel_material(size, radius, fill, border, border_width, priority)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## Text that reads on any background: cream with a dark outline.
static func style_label(label: Label3D, color := CREAM) -> void:
	label.modulate = color
	label.outline_modulate = INK
	label.render_priority = 10
	label.outline_render_priority = 9
