class_name ColonyGame
extends Node3D

const SECONDS_PER_DAY := 4.0

var simulation := ColonySimulation.new()
var site: LunarSite
var camera_rig: IsometricCamera
var hud: ColonyHUD
var paused := false
var speed := 1
var accumulator := 0.0
var tool := ""
var selected := Vector2i(999, 999)


func _ready() -> void:
	site = LunarSite.new()
	add_child(site)
	camera_rig = IsometricCamera.new()
	add_child(camera_rig)
	hud = ColonyHUD.new()
	add_child(hud)
	hud.tool_selected.connect(select_tool)
	hud.pause_requested.connect(toggle_pause)
	hud.speed_requested.connect(set_speed)
	hud.restart_requested.connect(restart)
	hud.camera_requested.connect(camera_command)
	simulation.changed.connect(refresh)
	simulation.notification.connect(func(message: String): hud.event_log.text = message)
	refresh()


func _process(delta: float) -> void:
	advance(delta)
	var point: Variant = ground_point(get_viewport().get_mouse_position())
	var over_ui := get_viewport().gui_get_hovered_control() != null
	if point == null or tool.is_empty() or over_ui:
		site.preview.visible = false
		return
	var cell := LunarSite.world_cell(point)
	var valid := tool_error(cell).is_empty()
	site.show_preview(cell, valid, simulation.is_inside(cell))


func advance(delta: float) -> void:
	if paused:
		return
	# Ignore long background/suspend gaps instead of fast-forwarding the colony.
	var elapsed_seconds := minf(delta, 0.25) * speed
	var elapsed_days := elapsed_seconds / SECONDS_PER_DAY
	simulation.advance(elapsed_days)
	accumulator = simulation.day_accumulator
	site.advance_modules(elapsed_seconds, simulation)
	hud.update_delivery_status(simulation, selected)


func tool_error(cell: Vector2i) -> String:
	match tool:
		"demolish":
			return "" if simulation.buildings.has(cell) else "Select an occupied tile to demolish."
		"bulldoze":
			return simulation.bulldoze_error(cell)
	return simulation.placement_error(tool, cell)


## Intersects the cursor ray with the displaced terrain by refining against the
## local surface height a few times (the relief is gentle, so this converges fast).
func ground_point(screen_position: Vector2) -> Variant:
	var camera := camera_rig.camera
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var height := 0.0
	var point: Variant = null
	for i in range(4):
		point = Plane(Vector3.UP, height).intersects_ray(origin, direction)
		if point == null:
			return null
		height = site.terrain.height_at(point.x, point.z)
	return point


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("speed_one"):
		set_speed(1)
	elif event.is_action_pressed("speed_two"):
		set_speed(2)
	elif event.is_action_pressed("speed_four"):
		set_speed(4)
	elif event.is_action_pressed("ui_cancel"):
		select_tool("")
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			select_tool("")
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var point: Variant = ground_point(event.position)
			if point != null:
				activate_cell(LunarSite.world_cell(point))


func activate_cell(cell: Vector2i) -> void:
	if tool == "demolish":
		simulation.demolish(cell)
	elif tool == "bulldoze":
		simulation.bulldoze(cell)
	elif not tool.is_empty():
		simulation.place(tool, cell)
	else:
		selected = cell
		hud.inspect(simulation, selected)


func select_tool(kind: String) -> void:
	tool = kind
	hud.set_tool(kind)
	site.preview.visible = false
	site.set_overlay(not kind.is_empty())


func toggle_pause() -> void:
	paused = not paused
	refresh()


func set_speed(value: int) -> void:
	speed = value
	refresh()


func restart() -> void:
	selected = Vector2i(999, 999)
	paused = false
	speed = 1
	accumulator = 0.0
	select_tool("")
	simulation.reset()


func camera_command(command: String) -> void:
	match command:
		"Left":
			camera_rig.pan(Vector2.LEFT * 2)
		"Right":
			camera_rig.pan(Vector2.RIGHT * 2)
		"Up":
			camera_rig.pan(Vector2.UP * 2)
		"Down":
			camera_rig.pan(Vector2.DOWN * 2)
		"Orbit -":
			camera_rig.orbit(-1)
		"Orbit +":
			camera_rig.orbit(1)
		"Zoom +":
			camera_rig.zoom(-1)
		"Zoom -":
			camera_rig.zoom(1)


func refresh() -> void:
	site.synchronize(simulation)
	hud.update_state(simulation, paused, speed, selected)
