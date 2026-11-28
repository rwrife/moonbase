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
const CYCLE_DAYS := 30
const DAYLIGHT_DAYS := 24
const TWILIGHT_DAYS := 1.5

const CONDITION_OPERATIONAL := "operational"
const CONDITION_DAMAGED := "damaged"
const CONDITION_REPAIRING := "repairing"
const VALID_CONDITIONS: Array[String] = [
	CONDITION_OPERATIONAL, CONDITION_DAMAGED, CONDITION_REPAIRING
]

const STARTER_LANDING_PAD_CELL := Vector2i(0, -2)
const SUPPLY_DELIVERY_AMOUNT := 4.0
const SUPPLY_DELIVERY_UNIT := "t"
const SUPPLY_DELIVERY_INTERVAL := 20.0
const SUPPLY_DELIVERY_INTERVAL_MIN := 14.0
const SUPPLY_DELIVERY_INTERVAL_MAX := 26.0
const DELIVERY_APPROACH_DURATION := 1.2
const DELIVERY_DESCEND_DURATION := 0.8
const DELIVERY_OFFLOAD_DURATION := 0.4
const DELIVERY_DEPART_DURATION := 0.6
const DELIVERY_VISIT_DURATION := (
	DELIVERY_APPROACH_DURATION + DELIVERY_DESCEND_DURATION
	+ DELIVERY_OFFLOAD_DURATION + DELIVERY_DEPART_DURATION
)
const STARTER_INITIAL_APPROACH_OFFSET := 0.2

var buildings: Dictionary = {}
## Cells flattened into construction pads (insertion order is grading order).
var graded: Dictionary = {}
## Cells covered by immovable landmark craters or boulders -> "crater" / "boulder".
var blocked: Dictionary = SiteSurvey.blocked_cells(MAP_RADIUS)
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
	_add(Vector2i(-3, 0), "ice")
	_add(Vector2i(-2, 0), "oxygen")
	_add(Vector2i(-1, 0), "habitat")
	_add(Vector2i(0, 0), "solar")
	var pad_id := _add(STARTER_LANDING_PAD_CELL, "landing_pad")
	if deliveries.has(pad_id):
		var entry: Dictionary = deliveries[pad_id]
		var approach_t := _delivery_approach_time(float(entry["interval"]))
		entry["cycle_time"] = approach_t + STARTER_INITIAL_APPROACH_OFFSET
		_refresh_delivery_phase(entry)
	last_report = "Founding grant received. Supply lander approaching; build reliable power before night."
	recalculate()
	changed.emit()


func _add(cell: Vector2i, kind: String) -> int:
	var id := next_id
	buildings[cell] = {
		"id": id,
		"kind": kind,
		"active": false,
		"network": -1,
		"build_progress": 1.0,
		"condition": CONDITION_OPERATIONAL,
		"repair_progress": 1.0,
	}
	graded[cell] = true
	next_id += 1
	if kind == "landing_pad":
		var entry := {
			"building_id": id,
			"cell": cell,
			"cycle_time": 0.0,
			"interval": _roll_delivery_interval(id, 1, cell),
			"phase": "waiting",
			"phase_progress": 0.0,
			"visit_id": 1,
			"cargo_credited": false,
		}
		_refresh_delivery_phase(entry)
		deliveries[id] = entry
	return id


static func _roll_delivery_interval(building_id: int, visit_id: int, cell: Vector2i) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_id, visit_id, cell.x, cell.y])
	rng.randf()
	var span := SUPPLY_DELIVERY_INTERVAL_MAX - SUPPLY_DELIVERY_INTERVAL_MIN
	return snappedf(SUPPLY_DELIVERY_INTERVAL_MIN + rng.randf() * span, 0.1)


static func _delivery_approach_time(interval: float) -> float:
	return maxf(0.0, interval - DELIVERY_VISIT_DURATION)


static func _delivery_credit_time(interval: float) -> float:
	return maxf(0.0, interval - DELIVERY_DEPART_DURATION)


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
		var approach_t := _delivery_approach_time(float(entry.get("interval", SUPPLY_DELIVERY_INTERVAL)))
		if not entry["cargo_credited"] and float(entry["cycle_time"]) >= approach_t:
			entry["cycle_time"] = 0.0
			_refresh_delivery_phase(entry)


func is_night() -> bool:
	return (day - 1) % CYCLE_DAYS >= DAYLIGHT_DAYS


func cycle_day() -> float:
	return float((day - 1) % CYCLE_DAYS) + clampf(day_accumulator, 0.0, 1.0)


## Returns a smooth illumination factor in [0.0, 1.0] (1.0 = full sunlight,
## 0.0 = full lunar night) with smoothstep dusk/dawn transitions.
func daylight_factor() -> float:
	var pos := cycle_day()
	var dusk_start := float(DAYLIGHT_DAYS) - TWILIGHT_DAYS
	var dawn_start := float(CYCLE_DAYS) - TWILIGHT_DAYS
	if pos < dusk_start:
		return 1.0
	if pos < float(DAYLIGHT_DAYS):
		return 1.0 - smoothstep(dusk_start, float(DAYLIGHT_DAYS), pos)
	if pos < dawn_start:
		return 0.0
	return smoothstep(dawn_start, float(CYCLE_DAYS), pos)


func is_inside(cell: Vector2i) -> bool:
	return absi(cell.x) <= MAP_RADIUS and absi(cell.y) <= MAP_RADIUS


func has_ice(cell: Vector2i) -> bool:
	return cell.x <= -3 and cell.y >= -4 and cell.y <= 4 and is_inside(cell)


func placement_error(kind: String, cell: Vector2i) -> String:
	if not BuildingCatalog.DATA.has(kind):
		return "Unknown building type."
	if not is_inside(cell):
		return "Outside the surveyed site."
	if buildings.has(cell):
		return "This tile is occupied."
	if blocked.has(cell):
		return "An immovable %s blocks this tile." % blocked[cell]
	if kind == "ice" and not has_ice(cell):
		return "Ice extractors require a frosted ice-deposit tile."
	if credits < float(BuildingCatalog.definition(kind)["cost"]):
		return "Insufficient credits."
	return ""


func place(kind: String, cell: Vector2i) -> bool:
	var error := placement_error(kind, cell)
	if not error.is_empty():
		report(error)
		return false
	credits -= float(BuildingCatalog.definition(kind)["cost"])
	_add(cell, kind)
	recalculate()
	report("%s commissioned." % BuildingCatalog.definition(kind)["name"])
	changed.emit()
	return true


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


func recalculate() -> void:
	networks.clear()
	crew = 0
	safe_crew = 0
	var visited: Dictionary = {}
	for origin: Vector2i in buildings:
		if visited.has(origin):
			continue
		var queue: Array[Vector2i] = [origin]
		var cells: Array[Vector2i] = []
		visited[origin] = true
		var cursor := 0
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			cells.append(cell)
			for direction in NEIGHBORS:
				var neighbor := cell + direction
				if buildings.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		var network := _evaluate_network(cells)
		var index := networks.size()
		networks.append(network)
		for cell in cells:
			buildings[cell]["network"] = index


func _evaluate_network(cells: Array[Vector2i]) -> Dictionary:
	var supply := {"power": 0.0, "water": 0.0, "oxygen": 0.0, "heat": 0.0}
	var demand := {"power": 0.0, "water": 0.0, "oxygen": 0.0, "heat": 0.0}
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			continue
		var kind: String = building["kind"]
		var data := BuildingCatalog.definition(kind)
		if kind != "solar" or not is_night():
			supply["power"] += float(data.get("power", 0))
		for utility: String in demand:
			demand[utility] += float(data.get(utility + "_use", 0))
		if kind == "habitat":
			crew += 8
	var powered: bool = supply["power"] >= demand["power"]
	# Evaluate dependencies from totals, never by consumer insertion order.
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			continue
		if building["kind"] == "ice" and powered:
			supply["water"] += float(BuildingCatalog.definition("ice")["water"])
	var watered: bool = supply["water"] >= demand["water"]
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			continue
		var kind: String = building["kind"]
		var data := BuildingCatalog.definition(kind)
		if kind == "reactor" or (kind == "oxygen" and powered and watered):
			supply["heat"] += float(data.get("heat", 0))
			supply["oxygen"] += float(data.get("oxygen", 0))
	var supported: bool = (
		powered and watered
		and supply["oxygen"] >= demand["oxygen"]
		and supply["heat"] >= demand["heat"]
	)
	for cell in cells:
		var building: Dictionary = buildings[cell]
		if not is_building_operational(building):
			building["active"] = false
			continue
		var kind: String = building["kind"]
		var active := powered
		match kind:
			"link", "reactor", "landing_pad":
				active = true
			"solar":
				active = not is_night()
			"oxygen":
				active = powered and watered
			"habitat":
				active = supported
				if active:
					safe_crew += 8
		building["active"] = active
	var shortages: Array[String] = []
	for utility: String in demand:
		if supply[utility] < demand[utility]:
			shortages.append(utility.capitalize())
	return {
		"cells": cells, "supply": supply, "demand": demand,
		"supported": supported, "shortages": shortages
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
			var interval: float = maxf(DELIVERY_VISIT_DURATION, float(entry.get("interval", SUPPLY_DELIVERY_INTERVAL)))
			var approach_t := _delivery_approach_time(interval)
			var credit_t := _delivery_credit_time(interval)
			var cycle_time: float = float(entry["cycle_time"])
			var credited: bool = bool(entry["cargo_credited"])
			if not operational:
				if credited:
					var to_depart := interval - cycle_time
					if remaining >= to_depart - 0.000001:
						entry["cycle_time"] = 0.0
						entry["cargo_credited"] = false
						entry["visit_id"] = int(entry["visit_id"]) + 1
						entry["interval"] = _roll_delivery_interval(id, int(entry["visit_id"]), cell)
						remaining = 0.0
					else:
						entry["cycle_time"] = cycle_time + remaining
						remaining = 0.0
				else:
					if cycle_time >= approach_t:
						entry["cycle_time"] = 0.0
					remaining = 0.0
				break
			if not credited:
				var to_credit := credit_t - cycle_time
				if remaining >= to_credit - 0.000001:
					remaining = maxf(0.0, remaining - maxf(0.0, to_credit))
					entry["cycle_time"] = credit_t
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
				var to_reset := interval - cycle_time
				if remaining >= to_reset - 0.000001:
					remaining = maxf(0.0, remaining - maxf(0.0, to_reset))
					entry["cycle_time"] = 0.0
					entry["cargo_credited"] = false
					entry["visit_id"] = int(entry["visit_id"]) + 1
					entry["interval"] = _roll_delivery_interval(id, int(entry["visit_id"]), cell)
				else:
					entry["cycle_time"] = cycle_time + remaining
					remaining = 0.0
		_refresh_delivery_phase(entry)
	return credited_any


func _refresh_delivery_phase(entry: Dictionary) -> void:
	var interval := maxf(DELIVERY_VISIT_DURATION, float(entry.get("interval", SUPPLY_DELIVERY_INTERVAL)))
	entry["interval"] = interval
	var approach_t := _delivery_approach_time(interval)
	var descend_t := approach_t + DELIVERY_APPROACH_DURATION
	var deliver_t := descend_t + DELIVERY_DESCEND_DURATION
	var credit_t := _delivery_credit_time(interval)
	var t := clampf(float(entry["cycle_time"]), 0.0, interval)
	entry["cycle_time"] = t
	if t < approach_t:
		entry["phase"] = "waiting"
		entry["phase_progress"] = (t / approach_t) if approach_t > 0.0 else 1.0
	elif t < descend_t:
		entry["phase"] = "approaching"
		entry["phase_progress"] = (t - approach_t) / DELIVERY_APPROACH_DURATION
	elif t < deliver_t:
		entry["phase"] = "descending"
		entry["phase_progress"] = (t - descend_t) / DELIVERY_DESCEND_DURATION
	elif t < credit_t:
		entry["phase"] = "delivering"
		entry["phase_progress"] = (t - deliver_t) / DELIVERY_OFFLOAD_DURATION
	else:
		entry["phase"] = "departing"
		entry["phase_progress"] = (t - credit_t) / DELIVERY_DEPART_DURATION


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
	var interval := maxf(DELIVERY_VISIT_DURATION, float(entry.get("interval", SUPPLY_DELIVERY_INTERVAL)))
	var t := float(entry["cycle_time"])
	var credit_t := _delivery_credit_time(interval)
	if not bool(entry["cargo_credited"]):
		return maxf(0.0, credit_t - t)
	var next_interval := _roll_delivery_interval(
		building_id, int(entry["visit_id"]) + 1, entry["cell"]
	)
	return maxf(0.0, (interval - t) + _delivery_credit_time(next_interval))


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
	if (day - 1) % CYCLE_DAYS == 0:
		var grant := 300.0 + minf(science * 2.0, 300.0)
		credits += grant
		report("Funding board awarded %.0f credits for this cycle." % grant)
	elif (day - 1) % CYCLE_DAYS == DAYLIGHT_DAYS:
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
	for network in networks:
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
			"build_progress": float(b.get("build_progress", 1.0)),
			"condition": str(b.get("condition", CONDITION_OPERATIONAL)),
			"repair_progress": float(b.get("repair_progress", 1.0)),
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
			"interval": float(d.get("interval", SUPPLY_DELIVERY_INTERVAL)),
			"visit_id": int(d["visit_id"]),
			"cargo_credited": bool(d["cargo_credited"]),
		})
	return {
		"version": 1,
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
		"deliveries": delivery_list,
	}


func import_state(state: Dictionary) -> bool:
	if int(state.get("version", 0)) != 1:
		return false
	buildings.clear()
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
		var kind := str(raw_b["kind"])
		if not BuildingCatalog.DATA.has(kind):
			continue
		var condition := str(raw_b.get("condition", CONDITION_OPERATIONAL))
		if not (condition in VALID_CONDITIONS):
			condition = CONDITION_OPERATIONAL
		buildings[cell] = {
			"id": int(raw_b["id"]),
			"kind": kind,
			"active": false,
			"network": -1,
			"build_progress": clampf(float(raw_b.get("build_progress", 1.0)), 0.0, 1.0),
			"condition": condition,
			"repair_progress": clampf(float(raw_b.get("repair_progress", 1.0)), 0.0, 1.0),
		}
		graded[cell] = true
		next_id = maxi(next_id, int(raw_b["id"]) + 1)
	for raw_d: Dictionary in state.get("deliveries", []):
		var raw_cell: Array = raw_d["cell"]
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var id := int(raw_d["building_id"])
		if not buildings.has(cell) or int(buildings[cell]["id"]) != id:
			continue
		if buildings[cell]["kind"] != "landing_pad":
			continue
		var visit_id := int(raw_d.get("visit_id", 1))
		var default_interval := _roll_delivery_interval(id, visit_id, cell)
		var interval := clampf(
			float(raw_d.get("interval", default_interval)),
			DELIVERY_VISIT_DURATION,
			SUPPLY_DELIVERY_INTERVAL_MAX
		)
		var entry := {
			"building_id": id,
			"cell": cell,
			"cycle_time": clampf(float(raw_d.get("cycle_time", 0.0)), 0.0, interval),
			"interval": interval,
			"phase": "waiting",
			"phase_progress": 0.0,
			"visit_id": visit_id,
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
				"interval": _roll_delivery_interval(int(b["id"]), 1, cell),
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
