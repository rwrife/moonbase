class_name ColonySimulation
extends RefCounted

signal changed
signal notification(message: String)

const MAP_RADIUS := 10
const NEIGHBORS: Array[Vector2i] = [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
]
const STARTING_CREDITS := 1800.0
const BULLDOZE_COST := 15.0

const CONDITION_OPERATIONAL := "operational"
const CONDITION_DAMAGED := "damaged"
const CONDITION_REPAIRING := "repairing"
const VALID_CONDITIONS: Array[String] = [
	CONDITION_OPERATIONAL, CONDITION_DAMAGED, CONDITION_REPAIRING
]

const STARTER_LANDING_PAD_CELL := Vector2i(0, -2)
const SUPPLY_DELIVERY_AMOUNT := 4.0
const SUPPLY_DELIVERY_UNIT := "t"
const SUPPLY_DELIVERY_INTERVAL := 6.0
const DELIVERY_PHASE_APPROACH := 3.0
const DELIVERY_PHASE_DESCEND := 4.2
const DELIVERY_PHASE_DELIVER := 5.0
const DELIVERY_CREDIT_TIME := 5.4
const STARTER_INITIAL_CYCLE_TIME := 3.2

var buildings: Dictionary = {}
## Dedicated HV power lines keyed by cell (can occupy open tiles or cross over tunnels).
var power_lines: Dictionary = {}
## Cells flattened into construction pads (insertion order is grading order).
var graded: Dictionary = {}
## Cells covered by immovable landmark craters or boulders -> "crater" / "boulder".
var blocked: Dictionary = SiteSurvey.blocked_cells(MAP_RADIUS)
## Authoritative electrical networks (traversing Power Connectors and Power Lines).
var power_networks: Array[Dictionary] = []
## Authoritative service corridor networks (humans, water, oxygen, heat, resources).
var service_networks: Array[Dictionary] = []
## Convenience alias matching service_networks for HUD/test compatibility.
var networks: Array[Dictionary] = []
## Independent delivery schedules keyed by landing pad building id.
var deliveries: Dictionary = {}
var credits := STARTING_CREDITS
var supplies := 0.0
var deliveries_completed := 0
var day := 1
var day_accumulator := 0.0
var morale := 85.0
var science := 0.0
var exports := 0.0
var crew := 0
var safe_crew := 0
var charter_complete := false
var last_report := ""
var next_id := 1


func _init() -> void:
	reset()


func reset() -> void:
	buildings.clear()
	power_lines.clear()
	graded.clear()
	deliveries.clear()
	credits = STARTING_CREDITS
	supplies = 0.0
	deliveries_completed = 0
	day = 1
	day_accumulator = 0.0
	morale = 85.0
	science = 0.0
	exports = 0.0
	next_id = 1
	charter_complete = false
	# Starter outpost demonstrates 2-port linear chaining + a 4-way adapter branching to solar.
	_add(Vector2i(-3, 0), "ice", 1, true)
	_add(Vector2i(-2, 0), "oxygen", 1, true)
	_add(Vector2i(-1, 0), "habitat", 1, true)
	_add(Vector2i(0, 0), "support_hub", 0, true)
	_add(Vector2i(0, 1), "solar", 2, true)
	var pad_id := _add(STARTER_LANDING_PAD_CELL, "landing_pad", 0, true)
	if deliveries.has(pad_id):
		deliveries[pad_id]["cycle_time"] = STARTER_INITIAL_CYCLE_TIME
		_refresh_delivery_phase(deliveries[pad_id])
	last_report = "Founding grant received. Supply lander approaching; build reliable power before night."
	recalculate()
	changed.emit()


func _add(cell: Vector2i, kind: String, facing: int = 0, auto_orient: bool = true) -> int:
	var canonical := BuildingCatalog.canonical_kind(kind)
	var id := next_id
	buildings[cell] = {
		"id": id,
		"kind": canonical,
		"facing": BuildingCatalog.normalize_facing(facing),
		"auto_orient": auto_orient,
		"service_mask": 0,
		"power_mask": 0,
		"active": false,
		"powered": false,
		"network": -1,
		"service_network": -1,
		"power_network": -1,
		"build_progress": 1.0,
		"condition": CONDITION_OPERATIONAL,
		"repair_progress": 1.0,
	}
	graded[cell] = true
	next_id += 1
	if canonical == "landing_pad":
		var entry := {
			"building_id": id,
			"cell": cell,
			"cycle_time": 0.0,
			"phase": "waiting",
			"phase_progress": 0.0,
			"visit_id": 1,
			"cargo_credited": false,
		}
		_refresh_delivery_phase(entry)
		deliveries[id] = entry
	return id


func _add_power_line(cell: Vector2i) -> int:
	var id := next_id
	power_lines[cell] = {
		"id": id,
		"power_mask": 0,
		"power_network": -1,
		"active": false,
	}
	next_id += 1
	return id


func is_building_operational(building: Dictionary) -> bool:
	return (
		float(building.get("build_progress", 1.0)) >= 1.0
		and str(building.get("condition", CONDITION_OPERATIONAL)) == CONDITION_OPERATIONAL
	)


func set_building_build_progress(cell: Vector2i, progress: float) -> bool:
	if not buildings.has(cell):
		return false
	buildings[cell]["build_progress"] = clampf(progress, 0.0, 1.0)
	_sync_delivery_for_pad_state(cell)
	recalculate()
	changed.emit()
	return true


func set_building_condition(cell: Vector2i, condition: String,
		repair_progress: float = -1.0) -> bool:
	if not buildings.has(cell) or not (condition in VALID_CONDITIONS):
		return false
	var building: Dictionary = buildings[cell]
	building["condition"] = condition
	if condition == CONDITION_OPERATIONAL:
		building["repair_progress"] = 1.0
	elif condition == CONDITION_DAMAGED:
		building["repair_progress"] = 0.0
	elif repair_progress >= 0.0:
		building["repair_progress"] = clampf(repair_progress, 0.0, 1.0)
	else:
		building["repair_progress"] = clampf(float(building.get("repair_progress", 0.0)), 0.0, 1.0)
	_sync_delivery_for_pad_state(cell)
	recalculate()
	changed.emit()
	return true


func _sync_delivery_for_pad_state(cell: Vector2i) -> void:
	if not buildings.has(cell):
		return
	var building: Dictionary = buildings[cell]
	if building["kind"] != "landing_pad":
		return
	var id: int = building["id"]
	if not deliveries.has(id):
		return
	if not is_building_operational(building):
		var entry: Dictionary = deliveries[id]
		if not entry["cargo_credited"] and float(entry["cycle_time"]) >= DELIVERY_PHASE_APPROACH:
			entry["cycle_time"] = 0.0
			_refresh_delivery_phase(entry)


func is_night() -> bool:
	return (day - 1) % 30 >= 20


func is_inside(cell: Vector2i) -> bool:
	return absi(cell.x) <= MAP_RADIUS and absi(cell.y) <= MAP_RADIUS


func has_ice(cell: Vector2i) -> bool:
	return cell.x <= -3 and cell.y >= -4 and cell.y <= 4 and is_inside(cell)


func has_service_port_toward(cell: Vector2i, direction: Vector2i) -> bool:
	if not buildings.has(cell):
		return false
	var b: Dictionary = buildings[cell]
	var ports := BuildingCatalog.world_service_ports(str(b["kind"]), int(b.get("facing", 0)))
	return direction in ports


func service_connected(a: Vector2i, b: Vector2i) -> bool:
	var direction := b - a
	return has_service_port_toward(a, direction) and has_service_port_toward(b, -direction)


func has_power_port_toward(cell: Vector2i, direction: Vector2i) -> bool:
	if power_lines.has(cell):
		return direction in BuildingCatalog.ALL_DIRS
	if not buildings.has(cell):
		return false
	var b: Dictionary = buildings[cell]
	var ports := BuildingCatalog.world_power_ports(str(b["kind"]), int(b.get("facing", 0)))
	return direction in ports


func power_connected(a: Vector2i, b: Vector2i) -> bool:
	var direction := b - a
	return has_power_port_toward(a, direction) and has_power_port_toward(b, -direction)


## Computes the best orientation (0..3) for a module at cell to align its Service/Power ports.
func compute_auto_facing(kind: String, cell: Vector2i) -> int:
	var canonical := BuildingCatalog.canonical_kind(kind)
	if not BuildingCatalog.has_kind(canonical):
		return 0
	if BuildingCatalog.is_power_only(canonical) or canonical in ["support_hub", "tunnel"]:
		return 0
	var best_facing := 0
	var best_score := -1
	for facing in range(4):
		var score := 0
		var s_ports := BuildingCatalog.world_service_ports(canonical, facing)
		var p_ports := BuildingCatalog.world_power_ports(canonical, facing)
		for dir in s_ports:
			var neighbor := cell + dir
			if buildings.has(neighbor):
				var nb: Dictionary = buildings[neighbor]
				if has_service_port_toward(neighbor, -dir):
					score += 100 if str(nb["kind"]) == "support_hub" else 50
				elif bool(nb.get("auto_orient", true)) and int(nb.get("service_mask", 0)) == 0:
					score += 18
		for dir in p_ports:
			var neighbor := cell + dir
			if power_lines.has(neighbor):
				score += 12
			elif buildings.has(neighbor) and has_power_port_toward(neighbor, -dir):
				score += 4
		if score > best_score:
			best_score = score
			best_facing = facing
	return best_facing


## Returns the preview connection masks { "service": int, "power": int } if kind is placed at cell.
func preview_connection_masks(kind: String, cell: Vector2i, facing: int) -> Dictionary:
	var canonical := BuildingCatalog.canonical_kind(kind)
	var s_mask := 0
	var p_mask := 0
	if not BuildingCatalog.has_kind(canonical):
		return {"service": 0, "power": 0}
	var s_ports := BuildingCatalog.world_service_ports(canonical, facing)
	var p_ports := BuildingCatalog.world_power_ports(canonical, facing)
	for dir in s_ports:
		var neighbor := cell + dir
		if has_service_port_toward(neighbor, -dir):
			s_mask |= BuildingCatalog.dir_bit(dir)
	for dir in p_ports:
		var neighbor := cell + dir
		if has_power_port_toward(neighbor, -dir):
			p_mask |= BuildingCatalog.dir_bit(dir)
	return {"service": s_mask, "power": p_mask}


func placement_error(kind: String, cell: Vector2i) -> String:
	if not BuildingCatalog.has_kind(kind):
		return "Unknown building type."
	var canonical := BuildingCatalog.canonical_kind(kind)
	if not is_inside(cell):
		return "Outside the surveyed site."
	if blocked.has(cell):
		return "An immovable %s blocks this tile." % blocked[cell]
	if canonical == "power_line":
		if power_lines.has(cell):
			return "This tile already has a power line."
		if buildings.has(cell) and str(buildings[cell]["kind"]) != "tunnel":
			return "This tile is occupied by a module."
		if credits < float(BuildingCatalog.definition(canonical)["cost"]):
			return "Insufficient credits."
		return ""
	if buildings.has(cell):
		return "This tile is occupied."
	if power_lines.has(cell) and canonical != "tunnel":
		return "Remove the power line on this tile first."
	if canonical == "ice" and not has_ice(cell):
		return "Ice extractors require a frosted ice-deposit tile."
	if credits < float(BuildingCatalog.definition(canonical)["cost"]):
		return "Insufficient credits."
	return ""


## Places a module or power line. Pass facing = -1 to auto-orient toward connected neighbors.
func place(kind: String, cell: Vector2i, facing: int = -1) -> bool:
	var error := placement_error(kind, cell)
	if not error.is_empty():
		report(error)
		return false
	var canonical := BuildingCatalog.canonical_kind(kind)
	credits -= float(BuildingCatalog.definition(canonical)["cost"])
	if canonical == "power_line":
		_add_power_line(cell)
	else:
		var auto_orient := facing < 0
		var chosen_facing := compute_auto_facing(canonical, cell) if auto_orient else BuildingCatalog.normalize_facing(facing)
		_add(cell, canonical, chosen_facing, auto_orient)
		_snap_isolated_auto_neighbors(cell)
	recalculate()
	report("%s commissioned." % BuildingCatalog.definition(canonical)["name"])
	changed.emit()
	return true


## Builds an orthogonal L-path between start and end, choosing the bend with fewer blocked tiles.
func compute_line_path(kind: String, start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var hv: Array[Vector2i] = []
	var vh: Array[Vector2i] = []
	var step_x := 1 if end.x >= start.x else -1
	var step_y := 1 if end.y >= start.y else -1
	var x := start.x
	while true:
		hv.append(Vector2i(x, start.y))
		if x == end.x:
			break
		x += step_x
	var y := start.y
	while y != end.y:
		y += step_y
		hv.append(Vector2i(end.x, y))

	y = start.y
	while true:
		vh.append(Vector2i(start.x, y))
		if y == end.y:
			break
		y += step_y
	x = start.x
	while x != end.x:
		x += step_x
		vh.append(Vector2i(x, end.y))

	return hv if _path_invalid_count(kind, hv) <= _path_invalid_count(kind, vh) else vh


func _path_invalid_count(kind: String, path: Array[Vector2i]) -> int:
	var canonical := BuildingCatalog.canonical_kind(kind)
	var invalid := 0
	for cell in path:
		if _is_existing_same_line(canonical, cell):
			continue
		if not _line_cell_geometry_error(canonical, cell).is_empty():
			invalid += 1
	return invalid


func _is_existing_same_line(canonical: String, cell: Vector2i) -> bool:
	if canonical == "power_line":
		return power_lines.has(cell)
	if canonical == "tunnel":
		return buildings.has(cell) and str(buildings[cell]["kind"]) == "tunnel"
	return false


func _line_cell_geometry_error(canonical: String, cell: Vector2i) -> String:
	if not is_inside(cell):
		return "Outside the surveyed site."
	if blocked.has(cell):
		return "An immovable %s blocks this tile." % blocked[cell]
	if canonical == "power_line":
		if buildings.has(cell) and str(buildings[cell]["kind"]) != "tunnel":
			return "This tile is occupied by a module."
		return ""
	if buildings.has(cell):
		return "This tile is occupied."
	return ""


## Places a dragged tunnel or power_line run atomically (skipping existing identical line tiles).
func place_line_path(kind: String, cells: Array[Vector2i]) -> int:
	var canonical := BuildingCatalog.canonical_kind(kind)
	if not BuildingCatalog.has_kind(canonical) or not BuildingCatalog.is_line_tool(canonical):
		report("Line routing requires a tunnel or power line tool.")
		return 0
	var to_place: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			continue
		seen[cell] = true
		if _is_existing_same_line(canonical, cell):
			continue
		var geom_err := _line_cell_geometry_error(canonical, cell)
		if not geom_err.is_empty():
			report(geom_err)
			return 0
		to_place.append(cell)
	if to_place.is_empty():
		report("Line is already in place along this path.")
		return 0
	var unit_cost := float(BuildingCatalog.definition(canonical)["cost"])
	var total_cost := unit_cost * float(to_place.size())
	if credits < total_cost:
		report("Insufficient credits (need %.0f cr for %d segments)." % [total_cost, to_place.size()])
		return 0
	credits -= total_cost
	for cell in to_place:
		if canonical == "power_line":
			_add_power_line(cell)
		else:
			_add(cell, canonical, 0, true)
			_snap_isolated_auto_neighbors(cell)
	recalculate()
	report("%s routed (%d segment%s)." % [
		BuildingCatalog.definition(canonical)["name"],
		to_place.size(),
		"" if to_place.size() == 1 else "s"
	])
	changed.emit()
	return to_place.size()


func _snap_isolated_auto_neighbors(placed_cell: Vector2i) -> void:
	for dir in BuildingCatalog.ALL_DIRS:
		var neighbor := placed_cell + dir
		if not buildings.has(neighbor):
			continue
		var nb: Dictionary = buildings[neighbor]
		if not bool(nb.get("auto_orient", true)):
			continue
		var nb_kind := str(nb["kind"])
		if nb_kind in ["support_hub", "tunnel"]:
			continue
		# Only auto-rotate an existing module if it has no existing service connections yet.
		var existing_links := 0
		for n_dir in BuildingCatalog.world_service_ports(nb_kind, int(nb.get("facing", 0))):
			var other := neighbor + n_dir
			if other == placed_cell:
				continue
			if has_service_port_toward(other, -n_dir):
				existing_links += 1
		if existing_links == 0:
			nb["facing"] = compute_auto_facing(nb_kind, neighbor)


func bulldoze_error(cell: Vector2i) -> String:
	if not is_inside(cell):
		return "Outside the surveyed site."
	if blocked.has(cell):
		return "An immovable %s cannot be cleared." % blocked[cell]
	if graded.has(cell):
		return "This tile is already a graded pad."
	if credits < BULLDOZE_COST:
		return "Insufficient credits."
	return ""


## Clears rocks and levels regolith into a pad. Construction grades for free.
func bulldoze(cell: Vector2i) -> bool:
	var error := bulldoze_error(cell)
	if not error.is_empty():
		report(error)
		return false
	credits -= BULLDOZE_COST
	graded[cell] = true
	report("Regolith graded into a level pad.")
	changed.emit()
	return true


func demolish(cell: Vector2i) -> bool:
	# If a power line crosses over a tunnel (or stands alone), remove the power line first.
	if power_lines.has(cell):
		credits += float(BuildingCatalog.definition("power_line")["cost"]) * 0.25
		power_lines.erase(cell)
		recalculate()
		report("Power line dismantled; 25% of construction cost recovered.")
		changed.emit()
		return true
	if not buildings.has(cell):
		report("Select an occupied tile to demolish.")
		return false
	var building: Dictionary = buildings[cell]
	var kind: String = building["kind"]
	var id: int = building["id"]
	credits += float(BuildingCatalog.definition(kind)["cost"]) * 0.25
	buildings.erase(cell)
	deliveries.erase(id)
	recalculate()
	report("Module dismantled; 25% of construction cost recovered.")
	changed.emit()
	return true


func report(message: String) -> void:
	last_report = message
	notification.emit(message)


func _refresh_connection_masks() -> void:
	for cell: Vector2i in buildings:
		var b: Dictionary = buildings[cell]
		var s_mask := 0
		var p_mask := 0
		for dir in BuildingCatalog.ALL_DIRS:
			var neighbor := cell + dir
			if service_connected(cell, neighbor):
				s_mask |= BuildingCatalog.dir_bit(dir)
			if power_connected(cell, neighbor):
				p_mask |= BuildingCatalog.dir_bit(dir)
		b["service_mask"] = s_mask
		b["power_mask"] = p_mask
	for cell: Vector2i in power_lines:
		var entry: Dictionary = power_lines[cell]
		var p_mask := 0
		for dir in BuildingCatalog.ALL_DIRS:
			var neighbor := cell + dir
			if power_connected(cell, neighbor):
				p_mask |= BuildingCatalog.dir_bit(dir)
		entry["power_mask"] = p_mask


func recalculate() -> void:
	power_networks.clear()
	service_networks.clear()
	networks.clear()
	crew = 0
	safe_crew = 0
	_refresh_connection_masks()

	# Pass 1: Electrical networks (mated Power Connectors + Power Lines).
	var power_visited: Dictionary = {}
	var power_nodes: Array[Vector2i] = []
	for cell: Vector2i in buildings:
		power_nodes.append(cell)
	for cell: Vector2i in power_lines:
		if not buildings.has(cell):
			power_nodes.append(cell)
	for origin in power_nodes:
		if power_visited.has(origin):
			continue
		var queue: Array[Vector2i] = [origin]
		var cells: Array[Vector2i] = []
		power_visited[origin] = true
		var cursor := 0
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			cells.append(cell)
			for direction in BuildingCatalog.ALL_DIRS:
				var neighbor := cell + direction
				if (buildings.has(neighbor) or power_lines.has(neighbor)) and not power_visited.has(neighbor):
					if power_connected(cell, neighbor):
						power_visited[neighbor] = true
						queue.append(neighbor)
		var p_net := _evaluate_power_network(cells)
		var p_index := power_networks.size()
		power_networks.append(p_net)
		for cell in cells:
			if buildings.has(cell):
				buildings[cell]["power_network"] = p_index
			if power_lines.has(cell):
				power_lines[cell]["power_network"] = p_index
				power_lines[cell]["active"] = bool(p_net["powered"]) and float(p_net["supply"]) > 0.0

	# Pass 2: Service networks (mated Service Connectors: humans, water, oxygen, heat, resources).
	var service_visited: Dictionary = {}
	for origin: Vector2i in buildings:
		if service_visited.has(origin):
			continue
		var queue: Array[Vector2i] = [origin]
		var cells: Array[Vector2i] = []
		service_visited[origin] = true
		var cursor := 0
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			cells.append(cell)
			for direction in BuildingCatalog.ALL_DIRS:
				var neighbor := cell + direction
				if buildings.has(neighbor) and not service_visited.has(neighbor):
					if service_connected(cell, neighbor):
						service_visited[neighbor] = true
						queue.append(neighbor)
		var s_net := _evaluate_service_network(cells)
		var s_index := service_networks.size()
		service_networks.append(s_net)
		for cell in cells:
			buildings[cell]["service_network"] = s_index
			buildings[cell]["network"] = s_index
	networks = service_networks


func _evaluate_power_network(cells: Array[Vector2i]) -> Dictionary:
	var supply := 0.0
	var demand := 0.0
	for cell in cells:
		if not buildings.has(cell):
			continue
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			continue
		var kind: String = building["kind"]
		var data := BuildingCatalog.definition(kind)
		if kind != "solar" or not is_night():
			supply += float(data.get("power", 0))
		demand += float(data.get("power_use", 0))
	var powered: bool = supply >= demand
	for cell in cells:
		if not buildings.has(cell):
			continue
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			building["powered"] = false
			continue
		var kind: String = building["kind"]
		match kind:
			"support_hub", "tunnel", "reactor", "landing_pad":
				building["powered"] = true
			"solar":
				building["powered"] = not is_night()
			_:
				building["powered"] = powered
	return {
		"cells": cells,
		"supply": supply,
		"demand": demand,
		"powered": powered,
	}


func _evaluate_service_network(cells: Array[Vector2i]) -> Dictionary:
	var supply := {"power": 0.0, "water": 0.0, "oxygen": 0.0, "heat": 0.0}
	var demand := {"power": 0.0, "water": 0.0, "oxygen": 0.0, "heat": 0.0}
	var seen_power_nets: Dictionary = {}
	var any_unpowered := false
	for cell in cells:
		var building: Dictionary = buildings[cell]
		var p_idx := int(building.get("power_network", -1))
		if p_idx >= 0 and not seen_power_nets.has(p_idx):
			seen_power_nets[p_idx] = true
			supply["power"] += float(power_networks[p_idx]["supply"])
			demand["power"] += float(power_networks[p_idx]["demand"])
		if not is_building_operational(building):
			continue
		var kind: String = building["kind"]
		var data := BuildingCatalog.definition(kind)
		for utility in ["water", "oxygen", "heat"]:
			demand[utility] += float(data.get(utility + "_use", 0))
		if kind == "habitat":
			crew += 8
		if float(data.get("power_use", 0)) > 0.0 and not bool(building["powered"]):
			any_unpowered = true

	# Water generation from powered ice extractors in this service corridor network.
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			continue
		if building["kind"] == "ice" and bool(building["powered"]):
			supply["water"] += float(BuildingCatalog.definition("ice")["water"])
	var watered: bool = supply["water"] >= demand["water"]

	# Oxygen & heat generation in this service corridor network.
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			continue
		var kind: String = building["kind"]
		var data := BuildingCatalog.definition(kind)
		if kind == "reactor" or (kind == "oxygen" and bool(building["powered"]) and watered):
			supply["heat"] += float(data.get("heat", 0))
			supply["oxygen"] += float(data.get("oxygen", 0))

	var service_supported: bool = (
		watered
		and supply["oxygen"] >= demand["oxygen"]
		and supply["heat"] >= demand["heat"]
	)

	# First activate infrastructure, generators, extractors, life support, and habitats.
	var local_safe_crew := 0
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			building["active"] = false
			continue
		var kind: String = building["kind"]
		var powered := bool(building["powered"])
		var active := powered
		match kind:
			"support_hub", "tunnel", "reactor", "landing_pad":
				active = true
			"solar":
				active = not is_night()
			"ice":
				active = powered
			"oxygen":
				active = powered and watered
			"habitat":
				active = powered and service_supported
				if active:
					local_safe_crew += 8
					safe_crew += 8
		building["active"] = active

	# Staffed production modules (lab, mine) require power AND service-corridor access to safe crew.
	var missing_crew_access := false
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			continue
		var data := BuildingCatalog.definition(str(building["kind"]))
		if bool(data.get("requires_crew_access", false)):
			var has_access := local_safe_crew > 0
			building["active"] = bool(building["powered"]) and has_access
			if not has_access:
				missing_crew_access = true

	var shortages: Array[String] = []
	if any_unpowered or supply["power"] < demand["power"]:
		shortages.append("Power")
	for utility in ["water", "oxygen", "heat"]:
		if supply[utility] < demand[utility]:
			shortages.append(utility.capitalize())
	if missing_crew_access:
		shortages.append("Crew access")
	return {
		"cells": cells,
		"supply": supply,
		"demand": demand,
		"supported": (not any_unpowered) and service_supported,
		"safe_crew": local_safe_crew,
		"shortages": shortages,
	}


func advance(elapsed_days: float) -> void:
	if elapsed_days <= 0.0:
		return
	var delivery_changed := advance_deliveries(elapsed_days)
	day_accumulator += elapsed_days
	var ticked := false
	while day_accumulator >= 1.0 - 0.000001:
		day_accumulator = maxf(0.0, day_accumulator - 1.0)
		_tick_day()
		ticked = true
	if delivery_changed and not ticked:
		changed.emit()


func advance_deliveries(elapsed_days: float) -> bool:
	if elapsed_days <= 0.0:
		return false
	var credited_any := false
	var ids: Array = deliveries.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = deliveries[id]
		var cell: Vector2i = entry["cell"]
		if not buildings.has(cell):
			deliveries.erase(id)
			continue
		var building: Dictionary = buildings[cell]
		var operational := is_building_operational(building) and bool(building["active"])
		var remaining := elapsed_days
		while remaining > 0.000001:
			var cycle_time: float = float(entry["cycle_time"])
			var credited: bool = bool(entry["cargo_credited"])
			if not operational:
				if credited:
					var to_depart := SUPPLY_DELIVERY_INTERVAL - cycle_time
					if remaining >= to_depart - 0.000001:
						entry["cycle_time"] = 0.0
						entry["cargo_credited"] = false
						entry["visit_id"] = int(entry["visit_id"]) + 1
						remaining = 0.0
					else:
						entry["cycle_time"] = cycle_time + remaining
						remaining = 0.0
				else:
					if cycle_time >= DELIVERY_PHASE_APPROACH:
						entry["cycle_time"] = 0.0
					remaining = 0.0
				break
			if not credited:
				var to_credit := DELIVERY_CREDIT_TIME - cycle_time
				if remaining >= to_credit - 0.000001:
					remaining = maxf(0.0, remaining - maxf(0.0, to_credit))
					entry["cycle_time"] = DELIVERY_CREDIT_TIME
					entry["cargo_credited"] = true
					supplies += SUPPLY_DELIVERY_AMOUNT
					deliveries_completed += 1
					credited_any = true
					report("Supply lander delivered %.0f %s supplies to Landing pad #%d." % [
						SUPPLY_DELIVERY_AMOUNT, SUPPLY_DELIVERY_UNIT, id
					])
				else:
					entry["cycle_time"] = cycle_time + remaining
					remaining = 0.0
			else:
				var to_reset := SUPPLY_DELIVERY_INTERVAL - cycle_time
				if remaining >= to_reset - 0.000001:
					remaining = maxf(0.0, remaining - maxf(0.0, to_reset))
					entry["cycle_time"] = 0.0
					entry["cargo_credited"] = false
					entry["visit_id"] = int(entry["visit_id"]) + 1
				else:
					entry["cycle_time"] = cycle_time + remaining
					remaining = 0.0
		_refresh_delivery_phase(entry)
	return credited_any


func _refresh_delivery_phase(entry: Dictionary) -> void:
	var t := clampf(float(entry["cycle_time"]), 0.0, SUPPLY_DELIVERY_INTERVAL)
	entry["cycle_time"] = t
	if t < DELIVERY_PHASE_APPROACH:
		entry["phase"] = "waiting"
		entry["phase_progress"] = t / DELIVERY_PHASE_APPROACH
	elif t < DELIVERY_PHASE_DESCEND:
		entry["phase"] = "approaching"
		entry["phase_progress"] = (t - DELIVERY_PHASE_APPROACH) / (
			DELIVERY_PHASE_DESCEND - DELIVERY_PHASE_APPROACH
		)
	elif t < DELIVERY_PHASE_DELIVER:
		entry["phase"] = "descending"
		entry["phase_progress"] = (t - DELIVERY_PHASE_DESCEND) / (
			DELIVERY_PHASE_DELIVER - DELIVERY_PHASE_DESCEND
		)
	elif t < DELIVERY_CREDIT_TIME:
		entry["phase"] = "delivering"
		entry["phase_progress"] = (t - DELIVERY_PHASE_DELIVER) / (
			DELIVERY_CREDIT_TIME - DELIVERY_PHASE_DELIVER
		)
	else:
		entry["phase"] = "departing"
		entry["phase_progress"] = (t - DELIVERY_CREDIT_TIME) / (
			SUPPLY_DELIVERY_INTERVAL - DELIVERY_CREDIT_TIME
		)


func delivery_for_cell(cell: Vector2i) -> Dictionary:
	if not buildings.has(cell):
		return {}
	var building: Dictionary = buildings[cell]
	if building["kind"] != "landing_pad":
		return {}
	return deliveries.get(building["id"], {})


func time_to_next_delivery(building_id: int) -> float:
	if not deliveries.has(building_id):
		return -1.0
	var entry: Dictionary = deliveries[building_id]
	var t := float(entry["cycle_time"])
	if not bool(entry["cargo_credited"]):
		return maxf(0.0, DELIVERY_CREDIT_TIME - t)
	return maxf(0.0, (SUPPLY_DELIVERY_INTERVAL - t) + DELIVERY_CREDIT_TIME)


func next_delivery_summary() -> Dictionary:
	var active_pads := 0
	var soonest := -1.0
	var next_phase := ""
	var next_cell := Vector2i(999, 999)
	for id: int in deliveries:
		var entry: Dictionary = deliveries[id]
		var cell: Vector2i = entry["cell"]
		if not buildings.has(cell):
			continue
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building) or not bool(building["active"]):
			continue
		active_pads += 1
		var remaining := time_to_next_delivery(id)
		if soonest < 0.0 or remaining < soonest:
			soonest = remaining
			next_phase = str(entry["phase"])
			next_cell = cell
	return {
		"active_pads": active_pads,
		"next_time": soonest,
		"next_phase": next_phase,
		"next_cell": next_cell,
	}


static func phase_label(phase: String) -> String:
	match phase:
		"waiting":
			return "Standby"
		"approaching":
			return "Approaching"
		"descending":
			return "Descending"
		"delivering":
			return "Offloading"
		"departing":
			return "Departing"
	return "Idle"


func tick() -> void:
	advance_deliveries(1.0)
	_tick_day()


func _tick_day() -> void:
	day += 1
	recalculate()
	var upkeep := 0.0
	var crew_safe := crew > 0 and safe_crew == crew
	for cell: Vector2i in buildings:
		var building: Dictionary = buildings[cell]
		var kind: String = building["kind"]
		upkeep += float(BuildingCatalog.definition(kind)["upkeep"])
		if building["active"] and crew_safe:
			if kind == "lab":
				science += 1.0
			elif kind == "mine":
				exports += 2.0
				credits += 24.0
	credits -= upkeep
	morale = clampf(morale + (0.5 if crew_safe else -3.0), 0.0, 100.0)
	if (day - 1) % 30 == 0:
		var grant := 300.0 + minf(science * 2.0, 300.0)
		credits += grant
		report("Funding board awarded %.0f credits for this cycle." % grant)
	elif (day - 1) % 30 == 20:
		report("Lunar night: solar arrays offline. Check power and heat.")
	elif not crew_safe:
		report("Life-support alert: %d/%d crew supplied. Inspect upstream utilities." % [
			safe_crew, crew
		])
	elif credits < 0:
		report("Budget deficit: exports or board funding are needed.")
	if (
		not charter_complete and day >= 30 and science >= 30 and exports >= 40
		and crew_safe and morale >= 65
	):
		charter_complete = true
		report("Founding charter complete! Continue expanding or restart.")
	changed.emit()


func totals(utility: String) -> Vector2:
	var result := Vector2.ZERO
	if utility == "power":
		for p_net in power_networks:
			result.x += float(p_net["supply"])
			result.y += float(p_net["demand"])
		return result
	for network in service_networks:
		result.x += float(network["supply"][utility])
		result.y += float(network["demand"][utility])
	return result


func export_state() -> Dictionary:
	var graded_list: Array = []
	for cell: Vector2i in graded:
		graded_list.append([cell.x, cell.y])
	var building_list: Array = []
	for cell: Vector2i in buildings:
		var b: Dictionary = buildings[cell]
		building_list.append({
			"cell": [cell.x, cell.y],
			"id": int(b["id"]),
			"kind": str(b["kind"]),
			"facing": int(b.get("facing", 0)),
			"auto_orient": bool(b.get("auto_orient", true)),
			"build_progress": float(b.get("build_progress", 1.0)),
			"condition": str(b.get("condition", CONDITION_OPERATIONAL)),
			"repair_progress": float(b.get("repair_progress", 1.0)),
		})
	var power_line_list: Array = []
	for cell: Vector2i in power_lines:
		var pl: Dictionary = power_lines[cell]
		power_line_list.append({
			"cell": [cell.x, cell.y],
			"id": int(pl["id"]),
		})
	var delivery_list: Array = []
	var ids: Array = deliveries.keys()
	ids.sort()
	for id: int in ids:
		var d: Dictionary = deliveries[id]
		var cell: Vector2i = d["cell"]
		delivery_list.append({
			"building_id": int(d["building_id"]),
			"cell": [cell.x, cell.y],
			"cycle_time": float(d["cycle_time"]),
			"visit_id": int(d["visit_id"]),
			"cargo_credited": bool(d["cargo_credited"]),
		})
	return {
		"version": 2,
		"day": day,
		"day_accumulator": day_accumulator,
		"credits": credits,
		"supplies": supplies,
		"deliveries_completed": deliveries_completed,
		"morale": morale,
		"science": science,
		"exports": exports,
		"charter_complete": charter_complete,
		"last_report": last_report,
		"next_id": next_id,
		"graded": graded_list,
		"buildings": building_list,
		"power_lines": power_line_list,
		"deliveries": delivery_list,
	}


func import_state(state: Dictionary) -> bool:
	var version := int(state.get("version", 0))
	if version != 1 and version != 2:
		return false
	buildings.clear()
	power_lines.clear()
	graded.clear()
	deliveries.clear()
	day = int(state.get("day", 1))
	day_accumulator = clampf(float(state.get("day_accumulator", 0.0)), 0.0, 1.0)
	credits = float(state.get("credits", STARTING_CREDITS))
	supplies = float(state.get("supplies", 0.0))
	deliveries_completed = int(state.get("deliveries_completed", 0))
	morale = clampf(float(state.get("morale", 85.0)), 0.0, 100.0)
	science = float(state.get("science", 0.0))
	exports = float(state.get("exports", 0.0))
	charter_complete = bool(state.get("charter_complete", false))
	last_report = str(state.get("last_report", ""))
	next_id = int(state.get("next_id", 1))
	for raw_cell: Array in state.get("graded", []):
		graded[Vector2i(int(raw_cell[0]), int(raw_cell[1]))] = true
	for raw_b: Dictionary in state.get("buildings", []):
		var raw_cell: Array = raw_b["cell"]
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var kind := BuildingCatalog.canonical_kind(str(raw_b["kind"]))
		if not BuildingCatalog.has_kind(kind) or BuildingCatalog.is_power_only(kind):
			continue
		var condition := str(raw_b.get("condition", CONDITION_OPERATIONAL))
		if not (condition in VALID_CONDITIONS):
			condition = CONDITION_OPERATIONAL
		var facing := BuildingCatalog.normalize_facing(int(raw_b.get("facing", 0)))
		var auto_orient := bool(raw_b.get("auto_orient", true))
		buildings[cell] = {
			"id": int(raw_b["id"]),
			"kind": kind,
			"facing": facing,
			"auto_orient": auto_orient,
			"service_mask": 0,
			"power_mask": 0,
			"active": false,
			"powered": false,
			"network": -1,
			"service_network": -1,
			"power_network": -1,
			"build_progress": clampf(float(raw_b.get("build_progress", 1.0)), 0.0, 1.0),
			"condition": condition,
			"repair_progress": clampf(float(raw_b.get("repair_progress", 1.0)), 0.0, 1.0),
		}
		graded[cell] = true
		next_id = maxi(next_id, int(raw_b["id"]) + 1)
	for raw_pl: Dictionary in state.get("power_lines", []):
		var raw_cell: Array = raw_pl["cell"]
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var id := int(raw_pl.get("id", next_id))
		power_lines[cell] = {
			"id": id,
			"power_mask": 0,
			"power_network": -1,
			"active": false,
		}
		next_id = maxi(next_id, id + 1)
	for raw_d: Dictionary in state.get("deliveries", []):
		var raw_cell: Array = raw_d["cell"]
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var id := int(raw_d["building_id"])
		if not buildings.has(cell) or int(buildings[cell]["id"]) != id:
			continue
		if buildings[cell]["kind"] != "landing_pad":
			continue
		var entry := {
			"building_id": id,
			"cell": cell,
			"cycle_time": clampf(float(raw_d.get("cycle_time", 0.0)), 0.0, SUPPLY_DELIVERY_INTERVAL),
			"phase": "waiting",
			"phase_progress": 0.0,
			"visit_id": int(raw_d.get("visit_id", 1)),
			"cargo_credited": bool(raw_d.get("cargo_credited", false)),
		}
		_refresh_delivery_phase(entry)
		deliveries[id] = entry
	# Ensure every restored landing pad has a delivery schedule.
	for cell: Vector2i in buildings:
		var b: Dictionary = buildings[cell]
		if b["kind"] == "landing_pad" and not deliveries.has(b["id"]):
			var entry := {
				"building_id": int(b["id"]),
				"cell": cell,
				"cycle_time": 0.0,
				"phase": "waiting",
				"phase_progress": 0.0,
				"visit_id": 1,
				"cargo_credited": false,
			}
			_refresh_delivery_phase(entry)
			deliveries[int(b["id"])] = entry
	recalculate()
	changed.emit()
	return true
