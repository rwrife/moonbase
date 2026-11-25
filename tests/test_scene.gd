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
	check_module_visuals(game)
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
		game.site.surface_position(Vector2i(0, 1)))
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
	var pad := Vector2i(4, -4)
	var rough := game.site.terrain.pad_targets.has(pad)
	var hidden_before := _visible_rocks(game.site, pad)
	game.select_tool("bulldoze")
	check(game.hud.tool_buttons["bulldoze"].button_pressed, "HUD must show bulldoze mode")
	game.activate_cell(pad)
	check(not rough and game.site.terrain.pad_targets.has(pad), "Bulldozing must grade the terrain")
	var level: float = game.site.terrain.pad_targets[pad]
	var center := LunarSite.cell_position(pad)
	var flat := true
	for offset in [Vector2(-0.9, -0.9), Vector2(0.9, 0.9), Vector2(0.9, -0.9), Vector2(0, 0)]:
		flat = flat and absf(game.site.terrain.height_at(center.x + offset.x, center.z + offset.y) - level) < 0.002
	check(flat, "Graded pad must be level")
	check(_visible_rocks(game.site, pad) == 0, "Bulldozing must clear rocks (had %d)" % hidden_before)
	var blocked: Vector2i = game.simulation.blocked.keys()[0]
	check(not game.tool_error(blocked).is_empty(), "Preview must reject immovable landmarks")
	game.select_tool("")
	game.activate_cell(blocked)
	check("Immovable" in game.hud.inspector.text, "Inspector must describe immovable terrain")
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
	check(not game.site.terrain.pad_targets.has(pad) and _visible_rocks(game.site, pad) == hidden_before,
		"Restart must restore undisturbed regolith and rocks")
	check(game.simulation.day == 1 and game.speed == 1 and not game.paused,
		"Restart must clear clock, pause, speed and scenario")
	game.simulation.demolish(Vector2i(0, 0))
	game.simulation.place("reactor", Vector2i(0, 0))
	game.restart()
	check(game.site.models[Vector2i(0, 0)].get_meta("kind") == "solar",
		"Restart must replace visuals when a starter module changed type")
	check(game.site.models[Vector2i(0, 0)].operating_time == 0.0,
		"Replacement starter modules must begin with a fresh animation clock")
	var cell := Vector2i(-3, 2)
	var screen: Vector2 = game.camera_rig.camera.unproject_position(game.site.surface_position(cell))
	check(LunarSite.world_cell(game.ground_point(screen)) == cell, "Camera ray must resolve grid cell")
	game.camera_command("Orbit +")
	screen = game.camera_rig.camera.unproject_position(game.site.surface_position(cell))
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


func _visible_rocks(site: LunarSite, cell: Vector2i) -> int:
	var count := 0
	for entry: Array in site.cell_rocks.get(cell, []):
		var transform: Transform3D = entry[0].get_instance_transform(entry[1])
		if transform.basis.get_scale().x > 0.0001 and LunarSite.world_cell(transform.origin) == cell:
			count += 1
	return count


func check_module_visuals(game: ColonyGame) -> void:
	var solar: LunarModule = game.site.models[Vector2i(0, 0)]
	var ice: LunarModule = game.site.models[Vector2i(-3, 0)]
	var oxygen: LunarModule = game.site.models[Vector2i(-2, 0)]
	var habitat: LunarModule = game.site.models[Vector2i(-1, 0)]
	var initial_rotation := ice.mechanism.rotation.y
	var initial_tracking := solar.mechanism.rotation.x
	var initial_pump := oxygen.mechanism.position.y
	game.advance(0.25)
	check(ice.mechanism.rotation.y != initial_rotation, "Powered extractor must turn its drill")
	check(solar.mechanism.rotation.x != initial_tracking, "Sunlit array must track slowly")
	check(oxygen.mechanism.position.y != initial_pump, "Active life support must stroke its pump")
	check(habitat.glass.emission_energy_multiplier > 0.0, "Supported habitat windows must be lit")
	check(ice.work_light.visible, "Powered service equipment must illuminate its work area")
	game.toggle_pause()
	var paused_rotation := ice.mechanism.rotation.y
	var paused_lamp: Material = ice.lamps[0].material_override
	game.advance(0.25)
	check(ice.mechanism.rotation.y == paused_rotation, "Pause must freeze operating mechanisms")
	check(ice.lamps[0].material_override == paused_lamp, "Pause must freeze telemetry animation")
	game.toggle_pause()
	game.set_speed(4)
	var before := ice.operating_time
	game.advance(0.1)
	check(is_equal_approx(ice.operating_time - before, 0.4), "Animation must follow game speed")
	game.simulation.day = 21
	game.simulation.recalculate()
	game.refresh()
	var night_tracking := solar.mechanism.rotation.x
	var night_drill := ice.mechanism.rotation.y
	game.advance(0.1)
	check(not solar.active and not ice.active and not oxygen.active and not habitat.active,
		"Night power loss must reach every starter module's operating state")
	check(solar.mechanism.rotation.x == night_tracking and ice.mechanism.rotation.y == night_drill,
		"Offline solar tracking and extraction must stop")
	check(habitat.glass.emission_energy_multiplier == 0.0, "Offline habitat windows must go dark")
	check(not ice.work_light.visible, "Offline work lights must turn off")
	check(oxygen.lamps.all(func(lamp: MeshInstance3D): return lamp.material_override == oxygen.unlit),
		"Offline equipment must not show running telemetry")
	game.simulation.place("reactor", Vector2i(0, 1))
	var reactor: LunarModule = game.site.models[Vector2i(0, 1)]
	check(reactor.active and ice.active and habitat.active and not solar.active,
		"Night reactor must restore consumers without claiming solar generation")
	for kind in ["link", "lab", "mine"]:
		var model := LunarModule.new()
		model.build(kind)
		model.set_active(true)
		model.advance(0.25)
		check(model.lamps.size() > 0, "Every module needs operating telemetry: " + kind)
		if kind != "link":
			check(model.mechanism != null, "Production module needs a functional mechanism: " + kind)
		model.free()
	for model: LunarModule in game.site.models.values():
		var bounds := module_bounds(model, model)
		check(bounds.position.x >= -LunarSite.CELL_SIZE * 0.5 - 0.001
			and bounds.end.x <= LunarSite.CELL_SIZE * 0.5 + 0.001
			and bounds.position.z >= -LunarSite.CELL_SIZE * 0.5 - 0.001
			and bounds.end.z <= LunarSite.CELL_SIZE * 0.5 + 0.001,
			"Detailed hardware must fit its construction cell: " + str(model.get_meta("kind")))
		check(bounds.size.y >= 1.7,
			"Starter and reactor silhouettes must be substantial: " + str(model.get_meta("kind")))
	game.restart()


func module_bounds(node: Node3D, model: LunarModule) -> AABB:
	var bounds := AABB()
	if node is MeshInstance3D:
		var transform := model.global_transform.affine_inverse() * node.global_transform
		bounds = transform * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			bounds = bounds.merge(module_bounds(child, model))
	return bounds
