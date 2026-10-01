extends Node
## Renders a PNG of every object in `experiment` into `output_folder`, named after
## the object id. Set the PNGs as the objects' `picture` (or a task's reference_image).
## Open reference_image_maker.tscn, pick the experiment in the Inspector, and press
## F6 (Run Current Scene). The window closes when done.

@export var experiment: Experiment
@export_dir var output_folder := "res://river/art/characters/pictures"
@export var image_size := 512
## Transparent by default, so the image sits cleanly on the task panel.
@export var background := Color(0, 0, 0, 0)
## Camera tilt; slightly from above reads well for characters and fish.
@export var camera_pitch_degrees := -8.0
## Turns the object around the vertical axis before shooting (0 = as it faces the camera).
@export var yaw_degrees := 0.0
## Render with the experiment skin's models instead of the objects' own visuals.
@export var use_experiment_skin := false


func _ready() -> void:
	if experiment == null:
		push_error("ReferenceImageMaker|ERROR: pick an experiment in the Inspector")
		get_tree().quit()
		return
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
	var configs := {}
	for task in experiment.tasks:
		for pool in task.get_pools():
			for cfg in pool.get_objects():
				configs[cfg.get_id()] = cfg
	var skin: RiverSkin = experiment.look if use_experiment_skin else null
	for cfg: RiverObjectConfig in configs.values():
		var visual := RiverObject.build_visual(cfg, skin.scene_for(cfg) if skin else null)
		visual.basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Basis.from_euler(cfg.start_tilt_degrees * (PI / 180.0))
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
