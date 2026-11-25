extends SceneTree

## Renders review screenshots of the lunar site. Requires a display (e.g. xvfb-run):
##   godot --path . --script tests/capture_views.gd -- --out <directory>


func _init() -> void:
	call_deferred("run")


func shoot(game: ColonyGame, path: String) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[args.find("--out") + 1] if "--out" in args else "user://"
	root.size = Vector2i(1600, 1000)
	var game: ColonyGame = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var only_new := "--only-new" in args
	await shoot(game, out + "/initial_gameplay.png")
	var camera := game.camera_rig
	if not only_new:
		game.hud.visible = false
		camera.rotation_degrees.y = 45
		camera.camera.size = 34
		await shoot(game, out + "/overview.png")
		camera.position = Vector3(-3.45, 0, 0)
		camera.camera.size = 12
		await shoot(game, out + "/starter_hardware.png")
		game.advance(0.25)
		await shoot(game, out + "/starter_operating.png")
		game.simulation.day = 21
		game.simulation.recalculate()
		game.refresh()
		await shoot(game, out + "/starter_offline.png")
		game.restart()
		camera.camera.size = 13
		camera.position = Vector3(-10, 0, 12)
		await shoot(game, out + "/closeup_rough.png")
		game.simulation.place("reactor", Vector2i(0, 1))
		game.simulation.place("lab", Vector2i(1, 1))
		game.simulation.place("mine", Vector2i(1, 0))
		for cell in [Vector2i(2, -1), Vector2i(3, -1), Vector2i(2, -2), Vector2i(3, -2)]:
			game.simulation.bulldoze(cell)
		camera.position = Vector3(1.5, 0, -0.5)
		camera.camera.size = 16
		await shoot(game, out + "/graded_base.png")
		game.select_tool("bulldoze")
		camera.camera.size = 34
		camera.position = Vector3.ZERO
		await shoot(game, out + "/build_overlay.png")
		game.select_tool("")
		camera.position = Vector3(18, 0, -18)
		camera.camera.size = 22
		camera.rotation_degrees.y = 135
		await shoot(game, out + "/landmark_crater.png")
		game.hud.visible = true
		camera.position = Vector3.ZERO
		camera.camera.size = 30
		camera.rotation_degrees.y = 45
		await shoot(game, out + "/with_hud.png")

	# Landing pad + supply lander sequence captures (day and night at gameplay zoom).
	game.restart()
	game.hud.visible = false
	camera.position = LunarSite.cell_position(ColonySimulation.STARTER_LANDING_PAD_CELL)
	camera.camera.size = 14
	camera.rotation_degrees.y = 45
	await shoot(game, out + "/landing_approach_day.png")
	# Advance into delivering on deck (t = 5.2 -> 2.0 days from initial 3.2).
	for i in range(8):
		game.advance(0.25)
	await shoot(game, out + "/landing_delivering_day.png")
	game.simulation.day = 21
	game.simulation.recalculate()
	game.refresh()
	await shoot(game, out + "/landing_delivering_night.png")

	# Shared construction (0%, 50%), damaged, repairing, and operational states (day and night).
	game.restart()
	game.hud.visible = false
	game.simulation.set_building_build_progress(Vector2i(-3, 0), 0.0)
	game.simulation.set_building_build_progress(Vector2i(-2, 0), 0.5)
	game.simulation.set_building_condition(Vector2i(-1, 0), ColonySimulation.CONDITION_DAMAGED)
	game.simulation.set_building_condition(Vector2i(0, 0), ColonySimulation.CONDITION_REPAIRING, 0.6)
	game.simulation.place("reactor", Vector2i(1, 0))
	game.advance(0.2)
	camera.position = Vector3(-2.3, 0, 0)
	camera.camera.size = 14
	camera.rotation_degrees.y = 45
	await shoot(game, out + "/structure_states_day.png")
	game.simulation.day = 21
	game.simulation.recalculate()
	game.refresh()
	await shoot(game, out + "/structure_states_night.png")
	quit()
