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

var buildings: Dictionary = {}
## Cells flattened into construction pads (insertion order is grading order).
var graded: Dictionary = {}
## Cells covered by immovable landmark craters or boulders -> "crater" / "boulder".
var blocked: Dictionary = SiteSurvey.blocked_cells(MAP_RADIUS)
var networks: Array[Dictionary] = []
var credits := STARTING_CREDITS
var day := 1
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
	credits = STARTING_CREDITS
	day = 1
	morale = 85.0
	science = 0.0
	exports = 0.0
	next_id = 1
	charter_complete = false
	_add(Vector2i(-3, 0), "ice")
	_add(Vector2i(-2, 0), "oxygen")
	_add(Vector2i(-1, 0), "habitat")
	_add(Vector2i(0, 0), "solar")
	last_report = "Founding grant received. Build reliable power before night."
	recalculate()
	changed.emit()


func _add(cell: Vector2i, kind: String) -> void:
	buildings[cell] = {"id": next_id, "kind": kind, "active": false, "network": -1}
	graded[cell] = true
	next_id += 1


func is_night() -> bool:
	return (day - 1) % 30 >= 20


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
	var kind: String = buildings[cell]["kind"]
	credits += float(BuildingCatalog.definition(kind)["cost"]) * 0.25
	buildings.erase(cell)
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
		var kind: String = buildings[cell]["kind"]
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
		if buildings[cell]["kind"] == "ice" and powered:
			supply["water"] += float(BuildingCatalog.definition("ice")["water"])
	var watered: bool = supply["water"] >= demand["water"]
	for cell in cells:
		var kind: String = buildings[cell]["kind"]
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
		var kind: String = buildings[cell]["kind"]
		var active := powered
		match kind:
			"link", "reactor":
				active = true
			"solar":
				active = not is_night()
			"oxygen":
				active = powered and watered
			"habitat":
				active = supported
				if active:
					safe_crew += 8
		buildings[cell]["active"] = active
	var shortages: Array[String] = []
	for utility: String in demand:
		if supply[utility] < demand[utility]:
			shortages.append(utility.capitalize())
	return {
		"cells": cells, "supply": supply, "demand": demand,
		"supported": supported, "shortages": shortages
	}


func tick() -> void:
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
	for network in networks:
		result.x += float(network["supply"][utility])
		result.y += float(network["demand"][utility])
	return result
