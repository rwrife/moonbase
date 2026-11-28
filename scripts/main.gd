class_name ColonyGame
extends Node3D

var simulation := ColonySimulation.new()
var site: LunarSite
var camera_rig: IsometricCamera
var hud: ColonyHUD
var paused := false
var speed := 1
var accumulator := 0.0
var tool := ""
var manual_facing := -1
var last_preview_facing := 0
var dragging_line := false
var drag_start_cell := Vector2i(999, 999)
var drag_path: Array[Vector2i] = []
var selected := Vector2i(999, 999)


func _ready() -> void:
	site = LunarSite.new()
	add_child(site)
	camera_rig = IsometricCamera.new()
	add_child(camera_rig)
	hud = ColonyHUD.new()
	add_child(hud)
	hud.tool_selected.connect(select_tool)
	hud.rotate_requested.connect(rotate_preview)
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
	if point == null or tool.is_empty() or (over_ui and not dragging_line):
		site.hide_previews()
		return
	var cell := LunarSite.world_cell(point)
	if dragging_line and BuildingCatalog.has_kind(tool) and BuildingCatalog.is_line_tool(tool):
		drag_path = simulation.compute_line_path(tool, drag_start_cell, cell)
		site.show_line_preview(tool, drag_path, simulation)
		return
	if not simulation.is_inside(cell):
		site.hide_previews()
		return
	var valid := tool_error(cell).is_empty()
	if BuildingCatalog.has_kind(tool):
		var effective_facing := effective_facing_for(tool, cell)
		last_preview_facing = effective_facing
		var masks := simulation.preview_connection_masks(tool, cell, effective_facing)
		site.show_module_preview(tool, cell, effective_facing, valid, true, masks)
	else:
		site.show_preview(cell, valid, true)


func effective_facing_for(kind: String, cell: Vector2i) -> int:
	if manual_facing >= 0:
		return BuildingCatalog.normalize_facing(manual_facing)
	return simulation.compute_auto_facing(kind, cell)


func advance(delta: float) -> void:
	if paused:
		return
	# Ignore long background/suspend gaps instead of fast-forwarding the colony.
	var elapsed := minf(delta, 0.25) * speed
	simulation.advance(elapsed)
	accumulator = simulation.day_accumulator
	site.advance_modules(elapsed, simulation)
	hud.update_delivery_status(simulation, selected)


func tool_error(cell: Vector2i) -> String:
	match tool:
		"demolish":
			return "" if (simulation.buildings.has(cell) or simulation.power_lines.has(cell)) else "Select an occupied tile to demolish."
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
	elif event.is_action_pressed("rotate_cw"):
		rotate_preview()
	elif event.is_action_pressed("ui_cancel"):
		if dragging_line:
			_cancel_line_drag()
		else:
			select_tool("")
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if dragging_line:
				_cancel_line_drag()
			else:
				select_tool("")
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var point: Variant = ground_point(event.position)
				if point != null:
					var cell := LunarSite.world_cell(point)
					if BuildingCatalog.has_kind(tool) and BuildingCatalog.is_line_tool(tool):
						dragging_line = true
						drag_start_cell = cell
						drag_path = [cell]
						site.show_line_preview(tool, drag_path, simulation)
					else:
						activate_cell(cell)
			elif dragging_line:
				var point: Variant = ground_point(event.position)
				var end_cell := LunarSite.world_cell(point) if point != null else drag_start_cell
				var path := simulation.compute_line_path(tool, drag_start_cell, end_cell)
				_cancel_line_drag()
				if path.size() == 1:
					simulation.place(tool, path[0])
				else:
					simulation.place_line_path(tool, path)


func _cancel_line_drag() -> void:
	dragging_line = false
	drag_start_cell = Vector2i(999, 999)
	drag_path.clear()
	site.path_preview_root.visible = false


func rotate_preview() -> void:
	if not BuildingCatalog.has_kind(tool):
		return
	var base := last_preview_facing if manual_facing < 0 else manual_facing
	manual_facing = BuildingCatalog.normalize_facing(base + 1)
	last_preview_facing = manual_facing
	hud.set_facing_mode(manual_facing)


func activate_cell(cell: Vector2i) -> void:
	if tool == "demolish":
		simulation.demolish(cell)
	elif tool == "bulldoze":
		simulation.bulldoze(cell)
	elif not tool.is_empty():
		simulation.place(tool, cell, manual_facing)
	else:
		selected = cell
		hud.inspect(simulation, selected)


func select_tool(kind: String) -> void:
	_cancel_line_drag()
	tool = BuildingCatalog.canonical_kind(kind) if BuildingCatalog.has_kind(kind) else kind
	manual_facing = -1
	hud.set_tool(tool)
	hud.set_facing_mode(manual_facing)
	site.hide_previews()
	site.set_overlay(not tool.is_empty())


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
