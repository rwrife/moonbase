extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game: ColonyGame = packed.instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.site.models.size() == 4, "Scene must display starter modules")
	check(game.camera_rig.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"Gameplay camera must be orthographic")
	for entry in [
		["pan_left", KEY_LEFT], ["pan_right", KEY_RIGHT],
		["pan_up", KEY_UP], ["pan_down", KEY_DOWN]
	]:
		var events := InputMap.action_get_events(entry[0])
		check(events[1].physical_keycode == entry[1], "Arrow key mapping must match " + entry[0])
	var button: Button = game.hud.tool_buttons["reactor"]
	await click(button.get_global_rect().get_center())
	check(game.tool == "reactor", "HUD must select construction mode")
	check(game.simulation.buildings.size() == 4, "UI clicks must not place world modules")
	var build_screen := game.camera_rig.camera.unproject_position(
		LunarSite.cell_position(Vector2i(0, 1)))
	await click(build_screen)
	check(game.site.models.size() == 5, "Construction must synchronize world visuals")
	var credits: float = game.simulation.credits
	await click(build_screen)
	check(game.simulation.credits == credits and game.site.models.size() == 5,
		"Clicking an occupied cell must not charge or add a duplicate visual")
	check(game.hud.event_log.text == "This tile is occupied.", "World rejection must reach HUD")
	game.select_tool("")
	game.activate_cell(Vector2i(0, 1))
	check("Fission reactor" in game.hud.inspector.text, "Selection must inspect local module")
	game.select_tool("demolish")
	game.activate_cell(Vector2i(0, 1))
	await process_frame
	check(game.site.models.size() == 4, "Demolition must remove visual module")
	game.toggle_pause()
	for i in range(8):
		game.advance(0.25)
	check(game.simulation.day == 1, "Pause must freeze simulation")
	game.toggle_pause()
	game.hud.speed_buttons[1].pressed.emit()
	check(game.speed == 1, "HUD must select 1x speed")
	for i in range(4):
		game.advance(0.25)
	check(game.simulation.day == 2, "1x must tick once per second")
	game.hud.speed_buttons[4].pressed.emit()
	check(game.speed == 4, "HUD must select 4x speed")
	for i in range(4):
		game.advance(0.25)
	check(game.simulation.day == 6, "4x must tick four times per second")
	game.advance(60)
	check(game.simulation.day == 7, "Background gaps must not fast-forward the colony")
	game.restart()
	check(game.simulation.day == 1 and game.speed == 1 and not game.paused,
		"Restart must clear clock, pause, speed and scenario")
	game.simulation.demolish(Vector2i(0, 0))
	game.simulation.place("reactor", Vector2i(0, 0))
	game.restart()
	check(game.site.models[Vector2i(0, 0)].get_meta("kind") == "solar",
		"Restart must replace visuals when a starter module changed type")
	var cell := Vector2i(-3, 2)
	var screen: Vector2 = game.camera_rig.camera.unproject_position(LunarSite.cell_position(cell))
	check(LunarSite.world_cell(game.ground_point(screen)) == cell, "Camera ray must resolve grid cell")
	game.camera_command("Orbit +")
	screen = game.camera_rig.camera.unproject_position(LunarSite.cell_position(cell))
	check(LunarSite.world_cell(game.ground_point(screen)) == cell, "Orbit must preserve grid mapping")
	game.site.show_preview(cell, false, true)
	check(game.site.preview.visible and game.site.preview.material_override == game.site.bad_material,
		"Invalid construction preview must visibly reject placement")
	for i in range(100):
		game.camera_command("Zoom +")
	check(game.camera_rig.camera.size == 12, "Zoom must respect lower bound")
	for i in range(100):
		game.camera_command("Zoom -")
	check(game.camera_rig.camera.size == 60, "Zoom must respect upper bound")
	var args := OS.get_cmdline_user_args()
	if "--capture" in args and DisplayServer.get_name() != "headless":
		game.restart()
		game.simulation.place("reactor", Vector2i(0, 1))
		game.simulation.place("lab", Vector2i(1, 1))
		game.simulation.place("mine", Vector2i(1, 0))
		game.camera_rig.camera.size = 27
		game.camera_rig.rotation_degrees.y = 45
		game.selected = Vector2i(0, 1)
		game.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		var path := args[args.find("--capture") + 1]
		check(root.get_texture().get_image().save_png(path) == OK, "Render capture must save")
	game.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: scene, HUD, construction, clock, restart and camera integration")
	quit(1 if failures else 0)
