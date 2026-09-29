extends Node
## Renders a PNG of every RiverObjectConfig (.tres) in `configs_folder` into
## `output_folder`, named after the config id. Use the PNGs as a task's
## reference_image. Open reference_image_maker.tscn, set the folders in the
## Inspector, and press F6 (Run Current Scene). The window closes when done.

@export_dir var configs_folder := "res://river/data/experiments/character_match/objects"
@export_dir var output_folder := "res://river/data/experiments/character_match/images"
@export var image_size := 512
## Transparent by default, so the image sits cleanly on the task panel.
@export var background := Color(0, 0, 0, 0)
## Camera tilt; slightly from above reads well for characters and fish.
@export var camera_pitch_degrees := -8.0
## Optional: render with a skin's model instead of the config's own visual.
@export var skin: RiverSkin


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(image_size, image_size)
	viewport.own_world_3d = true
	viewport.transparent_bg = background.a < 1.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = background
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	viewport.add_child(sun)

	var camera := Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)

	DirAccess.make_dir_recursive_absolute(output_folder)
	var count := 0
	for file in DirAccess.get_files_at(configs_folder):
		if not (file.ends_with(".tres") or file.ends_with(".tres.remap")):
			continue
		var cfg := load(configs_folder.path_join(file.trim_suffix(".remap"))) as RiverObjectConfig
		if cfg == null:
			continue
		var visual := RiverObject.build_visual(cfg, skin.scene_for(cfg) if skin else null)
		visual.basis = Basis.from_euler(cfg.initial_rotation_degrees * (PI / 180.0))
		viewport.add_child(visual)

		# Frame the object: its size fills ~85% of the image height.
		var distance := cfg.size * 0.5 / tan(deg_to_rad(camera.fov * 0.5)) / 0.85
		camera.rotation_degrees = Vector3(camera_pitch_degrees, 0, 0)
		camera.position = camera.basis.z * distance

		for i in 3:
			await RenderingServer.frame_post_draw
		var path := output_folder.path_join("%s.png" % cfg.get_id())
		viewport.get_texture().get_image().save_png(path)
		print("ReferenceImageMaker|INFO: wrote ", path)
		visual.queue_free()
		count += 1

	print("ReferenceImageMaker|INFO: %d images done" % count)
	get_tree().quit()
