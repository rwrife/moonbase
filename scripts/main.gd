class_name ColonyGame
extends Node3D

const AUTOSAVE_INTERVAL_DAYS := 5

var simulation := ColonySimulation.new()
var save_store := ColonySaveStore.new()
var site: LunarSite
var camera_rig: IsometricCamera
var hud: ColonyHUD
var paused := false
var speed := 1
var accumulator := 0.0
var tool := ""
var selected := Vector2i(999, 999)
var autosave_enabled := true
var last_autosave_day := 1
var autosave_charter_saved := false
var autosave_policy: ColonySaveStore.OverwritePolicy = ColonySaveStore.OverwritePolicy.SAME_COLONY_ONLY
var pending_overwrite_slot := ""
var pending_overwrite_policy: ColonySaveStore.OverwritePolicy = ColonySaveStore.OverwritePolicy.SAME_COLONY_ONLY
var pending_backup_slot := ""
var last_save_result: Dictionary = {}
var _web_visibility_cb: Variant = null
var _web_pagehide_cb: Variant = null


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
	hud.save_requested.connect(func(): save_game(ColonySaveStore.SLOT_MANUAL))
	hud.load_requested.connect(func(slot_id: String): load_game(slot_id))
	hud.confirm_overwrite_requested.connect(confirm_pending_overwrite)
	hud.restore_backup_requested.connect(restore_pending_backup)
	simulation.changed.connect(refresh)
	simulation.notification.connect(func(message: String): hud.event_log.text = message)
	_install_web_lifecycle_hooks()
	refresh()
	refresh_save_banner()


func _exit_tree() -> void:
	_remove_web_lifecycle_hooks()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		on_lifecycle_suspend()


func configure_save_store(store: ColonySaveStore) -> void:
	save_store = store
	pending_overwrite_slot = ""
	pending_backup_slot = ""
	last_save_result = {}
	refresh_save_banner()


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
	var elapsed := minf(delta, 0.25) * speed
	var prev_charter := simulation.charter_complete
	simulation.advance(elapsed)
	accumulator = simulation.day_accumulator
	site.advance_modules(elapsed, simulation)
	hud.update_delivery_status(simulation, selected)
	if autosave_enabled:
		if simulation.charter_complete and not prev_charter and not autosave_charter_saved:
			autosave_charter_saved = true
			try_autosave("charter")
		elif simulation.day >= last_autosave_day + AUTOSAVE_INTERVAL_DAYS:
			try_autosave("interval")


func save_game(slot_id: String = ColonySaveStore.SLOT_MANUAL,
		policy: ColonySaveStore.OverwritePolicy = ColonySaveStore.OverwritePolicy.SAME_COLONY_ONLY) -> Dictionary:
	var result := save_store.save_simulation(slot_id, simulation, policy)
	last_save_result = result
	if result["ok"]:
		pending_overwrite_slot = ""
		pending_backup_slot = ""
		if slot_id == ColonySaveStore.SLOT_AUTOSAVE:
			last_autosave_day = simulation.day
		var label := "Autosaved" if slot_id == ColonySaveStore.SLOT_AUTOSAVE else "Saved"
		var msg := "%s colony (Day %d)." % [label, simulation.day]
		hud.update_save_status(msg, false, false, false)
		if slot_id == ColonySaveStore.SLOT_MANUAL:
			simulation.report(msg)
	else:
		var code := str(result.get("error_code", ""))
		var err := str(result.get("error", "Save failed."))
		var can_confirm := (
			code == "colony_conflict"
			or code == "unsupported_version_protected"
			or code == "corrupt_file_protected"
		)
		var can_backup := bool(result.get("backup_available", false))
		if can_confirm:
			pending_overwrite_slot = slot_id
			pending_overwrite_policy = result.get(
				"recommended_policy", ColonySaveStore.OverwritePolicy.ALLOW_DIFFERENT_COLONY
			)
		else:
			pending_overwrite_slot = ""
		if can_backup:
			pending_backup_slot = slot_id
		var prefix := "SAVE WARNING: " if can_confirm else "SAVE ERROR: "
		hud.update_save_status(
			prefix + err, true, can_confirm, can_backup,
			"Confirm Overwrite (%s)" % slot_id,
			"Restore %s Backup" % slot_id
		)
		simulation.report(prefix + err)
	return result


func load_game(slot_id: String = ColonySaveStore.SLOT_MANUAL,
		from_backup: bool = false) -> Dictionary:
	var result := save_store.load_into_simulation(slot_id, simulation, from_backup)
	last_save_result = result
	if result["ok"]:
		selected = Vector2i(999, 999)
		select_tool("")
		accumulator = simulation.day_accumulator
		last_autosave_day = simulation.day
		autosave_charter_saved = simulation.charter_complete
		autosave_policy = ColonySaveStore.OverwritePolicy.SAME_COLONY_ONLY
		pending_overwrite_slot = ""
		pending_backup_slot = ""
		refresh()
		var parts: PackedStringArray = [
			"Loaded %s%s (Day %d)." % [
				slot_id,
				" backup" if from_backup else " save",
				simulation.day
			]
		]
		var migrated_from := int(result.get("migrated_from", 0))
		if migrated_from > 0:
			parts.append("Migrated from v%d to v%d." % [migrated_from, SaveSchema.CURRENT_VERSION])
		var msg := " ".join(parts)
		hud.update_save_status(msg, false, false, false)
		simulation.report(msg)
	else:
		var err := str(result.get("error", "Load failed."))
		var can_backup := (not from_backup) and bool(result.get("backup_available", false))
		pending_backup_slot = slot_id if can_backup else ""
		pending_overwrite_slot = ""
		var msg := "LOAD ERROR: " + err
		hud.update_save_status(
			msg, true, false, can_backup,
			"Confirm Overwrite",
			"Restore %s Backup" % slot_id
		)
		simulation.report(msg)
	return result


func confirm_pending_overwrite() -> Dictionary:
	if pending_overwrite_slot.is_empty():
		return {"ok": false, "error_code": "no_pending_action", "error": "No pending overwrite to confirm."}
	var slot_id := pending_overwrite_slot
	var policy := pending_overwrite_policy
	return save_game(slot_id, policy)


func restore_pending_backup() -> Dictionary:
	if pending_backup_slot.is_empty():
		return {"ok": false, "error_code": "no_pending_action", "error": "No backup recovery pending."}
	var slot_id := pending_backup_slot
	return load_game(slot_id, true)


func try_autosave(reason: String = "interval") -> Dictionary:
	if not autosave_enabled:
		return {"ok": false, "error_code": "autosave_disabled", "error": "Autosave is disabled."}
	if reason == "lifecycle" and simulation.is_fresh_starter_state():
		return {"ok": false, "error_code": "skipped_fresh", "error": "Skipped lifecycle autosave on fresh starter colony."}
	last_autosave_day = simulation.day
	return save_game(ColonySaveStore.SLOT_AUTOSAVE, autosave_policy)


func on_lifecycle_suspend() -> Dictionary:
	return try_autosave("lifecycle")


func refresh_save_banner() -> void:
	if hud == null:
		return
	var summary := save_store.status_summary(simulation.blocked)
	if not bool(summary["available"]):
		hud.update_save_status(
			"SAVE ERROR: " + str(summary["storage_error"]), true, false, false
		)
		return
	var manual: Dictionary = summary["manual"]
	var auto_slot: Dictionary = summary["autosave"]
	var alerts: PackedStringArray = []
	var can_backup := false
	pending_backup_slot = ""
	for pair in [
		[ColonySaveStore.SLOT_MANUAL, manual, summary["manual_backup"]],
		[ColonySaveStore.SLOT_AUTOSAVE, auto_slot, summary["autosave_backup"]],
	]:
		var slot_name: String = pair[0]
		var info: Dictionary = pair[1]
		var bak_info: Dictionary = pair[2]
		if bool(info["exists"]) and not bool(info["ok"]):
			alerts.append("%s unreadable (%s; preserved)" % [slot_name, info["error_code"]])
			if bool(bak_info["ok"]) and pending_backup_slot.is_empty():
				can_backup = true
				pending_backup_slot = slot_name
	if not alerts.is_empty():
		hud.update_save_status(
			"SAVE WARNING: " + "; ".join(alerts),
			true, false, can_backup,
			"Confirm Overwrite",
			"Restore %s Backup" % pending_backup_slot if can_backup else "Restore Backup"
		)
		return
	var parts: PackedStringArray = []
	if bool(manual["ok"]):
		parts.append("Manual Day %d" % int((manual["summary"] as Dictionary).get("day", 1)))
	if bool(auto_slot["ok"]):
		parts.append("Auto Day %d" % int((auto_slot["summary"] as Dictionary).get("day", 1)))
	if parts.is_empty():
		hud.update_save_status("Saves: none yet (autosaves every %d days)" % AUTOSAVE_INTERVAL_DAYS)
	else:
		hud.update_save_status("Saved: " + "  |  ".join(parts))


func _install_web_lifecycle_hooks() -> void:
	if not OS.has_feature("web"):
		return
	_web_visibility_cb = JavaScriptBridge.create_callback(_on_web_visibility_change)
	_web_pagehide_cb = JavaScriptBridge.create_callback(_on_web_pagehide)
	var doc := JavaScriptBridge.get_interface("document")
	var win := JavaScriptBridge.get_interface("window")
	if doc != null:
		doc.addEventListener("visibilitychange", _web_visibility_cb)
	if win != null:
		win.addEventListener("pagehide", _web_pagehide_cb)


func _remove_web_lifecycle_hooks() -> void:
	if not OS.has_feature("web"):
		return
	var doc := JavaScriptBridge.get_interface("document")
	var win := JavaScriptBridge.get_interface("window")
	if doc != null and _web_visibility_cb != null:
		doc.removeEventListener("visibilitychange", _web_visibility_cb)
	if win != null and _web_pagehide_cb != null:
		win.removeEventListener("pagehide", _web_pagehide_cb)
	_web_visibility_cb = null
	_web_pagehide_cb = null


func _on_web_visibility_change(_args: Array) -> void:
	var doc := JavaScriptBridge.get_interface("document")
	if doc != null and str(doc.visibilityState) == "hidden":
		on_lifecycle_suspend()


func _on_web_pagehide(_args: Array) -> void:
	on_lifecycle_suspend()


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
	# Starting a new colony assigns a fresh colony_id and never overwrites saved colonies.
	selected = Vector2i(999, 999)
	paused = false
	speed = 1
	accumulator = 0.0
	last_autosave_day = 1
	autosave_charter_saved = false
	autosave_policy = ColonySaveStore.OverwritePolicy.SAME_COLONY_ONLY
	pending_overwrite_slot = ""
	pending_backup_slot = ""
	select_tool("")
	simulation.reset()
	refresh_save_banner()


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

