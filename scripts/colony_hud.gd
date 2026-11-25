class_name ColonyHUD
extends CanvasLayer

signal tool_selected(kind: String)
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
	var right := _panel(root, Vector2(1, 0), Vector2(1, 1), Vector4(-310, 212, -16, -110))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var tools := VBoxContainer.new()
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tools)
	tools.add_child(_label("CONSTRUCTION", 20))
	tool_label = _label("Mode: Inspect")
	tools.add_child(tool_label)
	var inspect := _button("Inspect / cancel [Esc]", func(): tool_selected.emit(""))
	tools.add_child(inspect)
	for kind in BuildingCatalog.ORDER:
		var data := BuildingCatalog.definition(kind)
		var button := _button("%s  /  %d cr" % [data["name"], data["cost"]],
			func(): tool_selected.emit(kind))
		button.tooltip_text = data["description"]
		button.toggle_mode = true
		button.custom_minimum_size.y = 36
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
	inspector = _label("Click a module to inspect its local utility network.")
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
		"WASD/arrows pan  |  Q/E orbit  |  Wheel zoom  |  Right-click/Esc cancel  |  1/2/3 speed", 14))


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
	utilities.text = "Supply / demand: " + "   |   ".join(parts) + "   (local networks matter)"
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
		elif BuildingCatalog.DATA.has(kind):
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


func inspect(simulation: ColonySimulation, cell: Vector2i) -> void:
	if not simulation.buildings.has(cell):
		if not simulation.is_inside(cell):
			inspector.text = "Click a module to inspect its local utility network.\nFrosted ground contains ice."
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
	var data := BuildingCatalog.definition(building["kind"])
	var network: Dictionary = simulation.networks[building["network"]]
	var lines: PackedStringArray = [
		"%s #%d" % [data["name"], building["id"]],
		"Tile %d, %d  /  %s" % [cell.x, cell.y, _status_text(building)],
		str(data["description"]),
	]
	if building["kind"] == "landing_pad":
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
	lines.append("Local supply / demand:")
	for utility in ["power", "water", "oxygen", "heat"]:
		lines.append("%s: %.0f / %.0f" % [
			utility.capitalize(), network["supply"][utility], network["demand"][utility]
		])
	var shortages: Array[String] = network["shortages"]
	lines.append("Shortage: " + ("none" if shortages.is_empty() else ", ".join(shortages)))
	inspector.text = "\n".join(lines)
