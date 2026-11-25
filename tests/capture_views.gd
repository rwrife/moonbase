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
	await shoot(game, out + "/initial_gameplay.png")
	game.hud.visible = false
	var camera := game.camera_rig
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
	quit()
