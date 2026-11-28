class_name ColonyHUD
extends CanvasLayer

signal tool_selected(kind: String)
signal rotate_requested
signal pause_requested
signal speed_requested(value: int)
signal restart_requested
signal camera_requested(command: String)

var stats: Label
var utilities: Label
var logistics: Label
var objective: Label
var event_log: Label
var inspector: Label
var tool_label: Label
var facing_label: Label
var rotate_button: Button
var pause_button: Button
var speed_buttons: Dictionary = {}
var tool_buttons: Dictionary = {}
var mode := ""


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 17
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.047, 0.078, 0.96)
	panel_style.border_color = Color(0.18, 0.3, 0.4)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(14)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	root.theme = theme
	var top := _panel(root, Vector2(0, 0), Vector2(1, 0), Vector4(16, 16, -16, 168))
	var header := VBoxContainer.new()
	top.add_child(header)
	var title := _label("SELENE FRONTIER  /  POLAR OUTPOST", 23)
	title.add_theme_color_override("font_color", Color(0.45, 0.84, 0.9))
	header.add_child(title)
	stats = _label("")
	header.add_child(stats)
	utilities = _label("")
	header.add_child(utilities)
	logistics = _label("", 16)
	logistics.add_theme_color_override("font_color", Color(0.86, 0.78, 0.52))
	header.add_child(logistics)
	var controls := HBoxContainer.new()
	header.add_child(controls)
	pause_button = _button("Pause [Space]", func(): pause_requested.emit())
	controls.add_child(pause_button)
	for speed in [1, 2, 4]:
		var button := _button("%dx" % speed, func(): speed_requested.emit(speed))
		button.toggle_mode = true
		speed_buttons[speed] = button
		controls.add_child(button)
	controls.add_child(_button("Restart", func(): restart_requested.emit()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	for command in ["Left", "Right", "Up", "Down", "Orbit -", "Orbit +", "Zoom +", "Zoom -"]:
		controls.add_child(_button(command, func(): camera_requested.emit(command)))
	var right := _panel(root, Vector2(1, 0), Vector2(1, 1), Vector4(-325, 212, -16, -110))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var tools := VBoxContainer.new()
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tools)
	tools.add_child(_label("CONSTRUCTION", 20))
	tool_label = _label("Mode: Inspect")
	tools.add_child(tool_label)
	var orient_row := HBoxContainer.new()
	tools.add_child(orient_row)
	facing_label = _label("Facing: Auto", 15)
	facing_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orient_row.add_child(facing_label)
	rotate_button = _button("Rotate [R]", func(): rotate_requested.emit())
	orient_row.add_child(rotate_button)
	var inspect := _button("Inspect / cancel [Esc]", func(): tool_selected.emit(""))
	tools.add_child(inspect)
	var connectors_header := _label("CONNECTORS & LINES", 15)
	connectors_header.add_theme_color_override("font_color", Color(0.45, 0.84, 0.9))
	tools.add_child(connectors_header)
	var modules_header_added := false
	for kind in BuildingCatalog.ORDER:
		if not modules_header_added and not (kind in ["support_hub", "tunnel", "power_line"]):
			modules_header_added = true
			var modules_header := _label("MODULES", 15)
			modules_header.add_theme_color_override("font_color", Color(0.45, 0.84, 0.9))
			tools.add_child(modules_header)
		var data := BuildingCatalog.definition(kind)
		var button := _button("%s  /  %d cr" % [data["name"], data["cost"]],
			func(): tool_selected.emit(kind))
		button.tooltip_text = data["description"]
		button.toggle_mode = true
		button.custom_minimum_size.y = 34
		tool_buttons[kind] = button
		tools.add_child(button)
	var bulldoze := _button("Bulldoze pad  /  %d cr" % ColonySimulation.BULLDOZE_COST,
		func(): tool_selected.emit("bulldoze"))
	bulldoze.tooltip_text = "Clear rocks and level regolith into a construction pad."
	bulldoze.toggle_mode = true
	tool_buttons["bulldoze"] = bulldoze
	tools.add_child(bulldoze)
	var demolish := _button("Demolish  /  25% refund", func(): tool_selected.emit("demolish"))
	demolish.toggle_mode = true
	tool_buttons["demolish"] = demolish
	tools.add_child(demolish)
	tools.add_child(HSeparator.new())
	tools.add_child(_label("SELECTED MODULE", 19))
	inspector = _label("Click a module to inspect its power grid and service corridor.")
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tools.add_child(inspector)
	var left := _panel(root, Vector2(0, 0), Vector2(0, 0), Vector4(16, 212, 315, 340))
	var mission := VBoxContainer.new()
	left.add_child(mission)
	mission.add_child(_label("FOUNDING CHARTER", 20))
	objective = _label("")
	mission.add_child(objective)
	var bottom := _panel(root, Vector2(0, 1), Vector2(1, 1), Vector4(16, -98, -16, -16))
	var footer := VBoxContainer.new()
	bottom.add_child(footer)
	event_log = _label("")
	event_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(event_log)
	footer.add_child(_label(
		"WASD/arrows pan  |  Q/E orbit  |  Wheel zoom  |  R rotate  |  Drag tunnel/power line  |  Right-click/Esc cancel", 14))


func _panel(parent: Control, start: Vector2, end: Vector2, offsets: Vector4) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = start.x
	panel.anchor_top = start.y
	panel.anchor_right = end.x
	panel.anchor_bottom = end.y
	panel.offset_left = offsets.x
	panel.offset_top = offsets.y
	panel.offset_right = offsets.z
	panel.offset_bottom = offsets.w
	parent.add_child(panel)
	return panel


func _label(text: String, font_size: int = 17) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func set_tool(kind: String) -> void:
	mode = kind
	tool_label.text = "Mode: " + (
		"Inspect" if kind.is_empty() else
		"Demolish" if kind == "demolish" else
		"Bulldoze" if kind == "bulldoze" else BuildingCatalog.definition(kind)["name"]
	)
	for key: String in tool_buttons:
		tool_buttons[key].set_pressed_no_signal(key == kind)


func set_facing_mode(manual_facing: int) -> void:
	if manual_facing < 0:
		facing_label.text = "Facing: Auto"
	else:
		facing_label.text = "Facing: " + BuildingCatalog.facing_label(manual_facing)


func update_state(simulation: ColonySimulation, paused: bool, speed: int,
		selected: Vector2i) -> void:
	stats.text = "Day %d  /  %s   |   Credits %.0f   |   Supplies %.0f %s   |   Crew %d/%d safe   |   Morale %.0f%%" % [
		simulation.day, "NIGHT" if simulation.is_night() else "SUNLIGHT",
		simulation.credits, simulation.supplies, ColonySimulation.SUPPLY_DELIVERY_UNIT,
		simulation.safe_crew, simulation.crew, simulation.morale
	]
	var parts: PackedStringArray = []
	for utility in ["power", "water", "oxygen", "heat"]:
		var total := simulation.totals(utility)
		parts.append("%s %.0f/%.0f" % [utility.capitalize(), total.x, total.y])
	utilities.text = "Supply / demand: " + "   |   ".join(parts) + "   (power & service connections matter)"
	update_delivery_status(simulation, selected)
	objective.text = "Science %.0f/30   Exports %.0f/40\nDay %d/30   Morale >=65%%\n%s" % [
		simulation.science, simulation.exports, simulation.day,
		"CHARTER COMPLETE" if simulation.charter_complete else "Keep all crew supplied."
	]
	event_log.text = simulation.last_report
	pause_button.text = "Resume [Space]" if paused else "Pause [Space]"
	for value: int in speed_buttons:
		speed_buttons[value].set_pressed_no_signal(value == speed)
	for kind: String in tool_buttons:
		if kind == "bulldoze":
			tool_buttons[kind].disabled = simulation.credits < ColonySimulation.BULLDOZE_COST
		elif BuildingCatalog.has_kind(kind):
			tool_buttons[kind].disabled = (
				simulation.credits < float(BuildingCatalog.definition(kind)["cost"])
			)
	inspect(simulation, selected)


func update_delivery_status(simulation: ColonySimulation, selected: Vector2i) -> void:
	var summary := simulation.next_delivery_summary()
	var active_pads: int = summary["active_pads"]
	if active_pads > 0:
		logistics.text = "Supply pads: %d active (+%.0f %s / %.0fd each)   |   Next landing: %.1fd (%s)" % [
			active_pads,
			ColonySimulation.SUPPLY_DELIVERY_AMOUNT,
			ColonySimulation.SUPPLY_DELIVERY_UNIT,
			ColonySimulation.SUPPLY_DELIVERY_INTERVAL,
			float(summary["next_time"]),
			ColonySimulation.phase_label(str(summary["next_phase"]))
		]
	else:
		logistics.text = "Supply pads: 0 active  (Build a Landing pad for +%.0f %s every %.0fd)" % [
			ColonySimulation.SUPPLY_DELIVERY_AMOUNT,
			ColonySimulation.SUPPLY_DELIVERY_UNIT,
			ColonySimulation.SUPPLY_DELIVERY_INTERVAL
		]
	if simulation.buildings.has(selected) and simulation.buildings[selected]["kind"] == "landing_pad":
		inspect(simulation, selected)


func _status_text(building: Dictionary) -> String:
	var build_p := float(building.get("build_progress", 1.0))
	if build_p < 1.0:
		return "UNDER CONSTRUCTION (%.0f%%)" % (build_p * 100.0)
	var cond := str(building.get("condition", ColonySimulation.CONDITION_OPERATIONAL))
	if cond == ColonySimulation.CONDITION_DAMAGED:
		return "DAMAGED (FAULT)"
	if cond == ColonySimulation.CONDITION_REPAIRING:
		return "UNDER REPAIR (%.0f%%)" % (float(building.get("repair_progress", 0.0)) * 100.0)
	return "ONLINE" if building["active"] else "OFFLINE"


func _mask_summary(mask: int) -> String:
	var dirs: PackedStringArray = []
	if (mask & BuildingCatalog.BIT_N) != 0:
		dirs.append("N")
	if (mask & BuildingCatalog.BIT_E) != 0:
		dirs.append("E")
	if (mask & BuildingCatalog.BIT_S) != 0:
		dirs.append("S")
	if (mask & BuildingCatalog.BIT_W) != 0:
		dirs.append("W")
	return "none" if dirs.is_empty() else "/".join(dirs)


func inspect(simulation: ColonySimulation, cell: Vector2i) -> void:
	if not simulation.buildings.has(cell):
		if simulation.power_lines.has(cell):
			var pl: Dictionary = simulation.power_lines[cell]
			var p_idx := int(pl.get("power_network", -1))
			var lines: PackedStringArray = [
				"Power line #%d" % int(pl["id"]),
				"Tile %d, %d  /  %s" % [cell.x, cell.y, "ENERGIZED" if bool(pl["active"]) else "UNPOWERED"],
				"Links: " + _mask_summary(int(pl["power_mask"])),
			]
			if p_idx >= 0 and p_idx < simulation.power_networks.size():
				var p_net: Dictionary = simulation.power_networks[p_idx]
				lines.append("Power grid: %.0f / %.0f" % [float(p_net["supply"]), float(p_net["demand"])])
			lines.append("Carries electricity only (does not pass crew, water, oxygen or heat).")
			inspector.text = "\n".join(lines)
			return
		if not simulation.is_inside(cell):
			inspector.text = "Click a module to inspect its power grid and service corridor.\nFrosted ground contains ice."
			return
		var lines: PackedStringArray = ["Tile %d, %d" % [cell.x, cell.y]]
		if simulation.blocked.has(cell):
			lines.append("Immovable %s: cannot be built on." % simulation.blocked[cell])
		elif simulation.graded.has(cell):
			lines.append("Graded construction pad.")
		else:
			lines.append("Rough regolith: bulldoze or build to level it.")
		if simulation.has_ice(cell):
			lines.append("Ice deposit: suitable for an ice extractor.")
		inspector.text = "\n".join(lines)
		return
	var building: Dictionary = simulation.buildings[cell]
	var kind: String = building["kind"]
	var data := BuildingCatalog.definition(kind)
	var s_idx := int(building.get("service_network", building["network"]))
	var p_idx := int(building.get("power_network", -1))
	var network: Dictionary = simulation.service_networks[s_idx]
	var lines: PackedStringArray = [
		"%s #%d" % [data["name"], building["id"]],
		"Tile %d, %d  /  %s" % [cell.x, cell.y, _status_text(building)],
		"Facing: %s" % BuildingCatalog.facing_label(int(building.get("facing", 0))),
		"Service ports mated: %s  |  Power: %s" % [
			_mask_summary(int(building.get("service_mask", 0))),
			_mask_summary(int(building.get("power_mask", 0)))
		],
		str(data["description"]),
	]
	if simulation.power_lines.has(cell):
		lines.append("Overhead HV power line crossing present.")
	if kind == "landing_pad":
		var delivery := simulation.delivery_for_cell(cell)
		if not delivery.is_empty():
			var next_t := simulation.time_to_next_delivery(int(building["id"]))
			lines.append("Lander: %s  /  Next +%.0f %s in %.1fd" % [
				ColonySimulation.phase_label(str(delivery["phase"])),
				ColonySimulation.SUPPLY_DELIVERY_AMOUNT,
				ColonySimulation.SUPPLY_DELIVERY_UNIT,
				next_t
			])
			lines.append("Colony supplies: %.0f %s" % [
				simulation.supplies, ColonySimulation.SUPPLY_DELIVERY_UNIT
			])
	lines.append("")
	if p_idx >= 0 and p_idx < simulation.power_networks.size():
		var p_net: Dictionary = simulation.power_networks[p_idx]
		lines.append("Power grid: %.0f / %.0f" % [float(p_net["supply"]), float(p_net["demand"])])
	lines.append("Service corridor:")
	for utility in ["water", "oxygen", "heat"]:
		lines.append("  %s: %.0f / %.0f" % [
			utility.capitalize(), network["supply"][utility], network["demand"][utility]
		])
	var shortages: Array[String] = network["shortages"]
	lines.append("Shortage: " + ("none" if shortages.is_empty() else ", ".join(shortages)))
	if "Crew access" in shortages:
		lines.append("Tip: Connect a Service Connector, Connection tunnel or 4-Way adapter to a supplied Habitat.")
	elif "Power" in shortages:
		lines.append("Tip: Run a Power line or connect to a powered module.")
	inspector.text = "\n".join(lines)
