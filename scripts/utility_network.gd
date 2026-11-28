class_name UtilityNetwork
extends RefCounted

## Deterministic layered utility network solver for power, water, oxygen and heat.
##
## Convergence rule:
## - Connected components are built independently per utility layer using sorted
##   (x, y) cell order, never dictionary insertion order.
## - Dependency evaluation runs as a bounded fixed-point iteration (MAX_ITERATIONS)
##   from a conservative snapshot where only unconditional/self-powered generators
##   and available storage discharge start active.
## - Within each iteration, every layer reads only from the previous snapshot's
##   active set, allocates supply strictly by priority tier (Life Support ->
##   Habitats -> Production) and sorted cell coordinates, and writes the next
##   snapshot. If a dependency cycle oscillates, the solver detects the repeated
##   snapshot state and resolves to the conservative intersection of the cycle.

const LAYERS: Array[String] = ["power", "water", "oxygen", "heat"]
const NEIGHBORS: Array[Vector2i] = [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
]

const PRIORITY_INFRASTRUCTURE := 0
const PRIORITY_LIFE_SUPPORT := 1
const PRIORITY_HABITAT := 2
const PRIORITY_PRODUCTION := 3
const PRIORITY_STORAGE := 4

const RESERVE_POLICY_BALANCED := "balanced"
const RESERVE_POLICY_PROTECT_ESSENTIAL := "protect_essential"
const VALID_RESERVE_POLICIES: Array[String] = [
	RESERVE_POLICY_BALANCED, RESERVE_POLICY_PROTECT_ESSENTIAL
]

const MAX_ITERATIONS := 16
const EPSILON := 0.000001


static func default_priority(kind: String, data: Dictionary) -> int:
	if data.has("priority"):
		return int(data["priority"])
	match kind:
		"link", "solar", "reactor", "landing_pad":
			return PRIORITY_INFRASTRUCTURE
		"ice", "oxygen":
			return PRIORITY_LIFE_SUPPORT
		"habitat":
			return PRIORITY_HABITAT
		"lab", "mine":
			return PRIORITY_PRODUCTION
	for layer in LAYERS:
		if float(data.get(layer + "_storage", 0.0)) > 0.0:
			return PRIORITY_STORAGE
	return PRIORITY_PRODUCTION


static func building_priority(building: Dictionary, data: Dictionary) -> int:
	if building.has("priority_override") and int(building["priority_override"]) >= 0:
		return int(building["priority_override"])
	return default_priority(str(building["kind"]), data)


static func is_operational(building: Dictionary) -> bool:
	return (
		float(building.get("build_progress", 1.0)) >= 1.0
		and str(building.get("condition", "operational")) == "operational"
	)


static func is_isolated(building: Dictionary) -> bool:
	return bool(building.get("isolated", false))


static func supports_layer(building: Dictionary, data: Dictionary, layer: String) -> bool:
	var layers_list: Variant = building.get("layers", data.get("layers", LAYERS))
	if layers_list is Array:
		return layer in layers_list
	return true


static func has_port(building: Dictionary, data: Dictionary, layer: String,
		direction: Vector2i) -> bool:
	if is_isolated(building):
		return false
	if not supports_layer(building, data, layer):
		return false
	var ports: Variant = building.get("ports", data.get("ports", null))
	if ports is Dictionary and ports.has(layer):
		var allowed: Variant = ports[layer]
		if allowed is Array:
			return direction in allowed
	return true


static func can_connect(cell_a: Vector2i, building_a: Dictionary, data_a: Dictionary,
		cell_b: Vector2i, building_b: Dictionary, data_b: Dictionary, layer: String) -> bool:
	var delta := cell_b - cell_a
	if not (delta in NEIGHBORS):
		return false
	return (
		has_port(building_a, data_a, layer, delta)
		and has_port(building_b, data_b, layer, -delta)
	)


static func _sorted_cells(buildings: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in buildings:
		cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return cells


static func _sort_cells_in_place(cells: Array[Vector2i]) -> void:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)


static func _building_def(building: Dictionary, catalog: Dictionary) -> Dictionary:
	return catalog.get(str(building["kind"]), {})


static func build_layer_components(buildings: Dictionary,
		catalog: Dictionary = BuildingCatalog.DATA) -> Dictionary:
	var all_cells := _sorted_cells(buildings)
	var result: Dictionary = {}
	for layer in LAYERS:
		var visited: Dictionary = {}
		var components: Array[Dictionary] = []
		var cell_to_comp: Dictionary = {}
		for origin in all_cells:
			if visited.has(origin):
				continue
			var b_origin: Dictionary = buildings[origin]
			var d_origin := _building_def(b_origin, catalog)
			if not supports_layer(b_origin, d_origin, layer):
				continue
			var queue: Array[Vector2i] = [origin]
			var comp_cells: Array[Vector2i] = []
			visited[origin] = true
			var cursor := 0
			while cursor < queue.size():
				var cell := queue[cursor]
				cursor += 1
				comp_cells.append(cell)
				var b_cur: Dictionary = buildings[cell]
				var d_cur := _building_def(b_cur, catalog)
				for direction in NEIGHBORS:
					var neighbor := cell + direction
					if not buildings.has(neighbor) or visited.has(neighbor):
						continue
					var b_next: Dictionary = buildings[neighbor]
					var d_next := _building_def(b_next, catalog)
					if can_connect(cell, b_cur, d_cur, neighbor, b_next, d_next, layer):
						visited[neighbor] = true
						queue.append(neighbor)
			_sort_cells_in_place(comp_cells)
			var comp_id := components.size()
			for c in comp_cells:
				cell_to_comp[c] = comp_id
			components.append({
				"id": comp_id,
				"layer": layer,
				"cells": comp_cells,
			})
		result[layer] = {
			"components": components,
			"cell_to_component": cell_to_comp,
		}
	return result


static func _build_union_components(buildings: Dictionary,
		catalog: Dictionary) -> Array[Array]:
	var all_cells := _sorted_cells(buildings)
	var visited: Dictionary = {}
	var groups: Array[Array] = []
	for origin in all_cells:
		if visited.has(origin):
			continue
		var queue: Array[Vector2i] = [origin]
		var group: Array[Vector2i] = []
		visited[origin] = true
		var cursor := 0
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			group.append(cell)
			var b_cur: Dictionary = buildings[cell]
			var d_cur := _building_def(b_cur, catalog)
			for direction in NEIGHBORS:
				var neighbor := cell + direction
				if not buildings.has(neighbor) or visited.has(neighbor):
					continue
				var b_next: Dictionary = buildings[neighbor]
				var d_next := _building_def(b_next, catalog)
				var linked := false
				for layer in LAYERS:
					if can_connect(cell, b_cur, d_cur, neighbor, b_next, d_next, layer):
						linked = true
						break
				if linked:
					visited[neighbor] = true
					queue.append(neighbor)
		_sort_cells_in_place(group)
		groups.append(group)
	return groups


static func _has_any_demand(data: Dictionary) -> bool:
	for layer in LAYERS:
		if float(data.get(layer + "_use", 0.0)) > EPSILON:
			return true
	return false


static func _raw_production(building: Dictionary, data: Dictionary,
		layer: String, is_night: bool, is_active: bool) -> float:
	if not is_operational(building) or is_isolated(building):
		return 0.0
	var base := float(data.get(layer, 0.0))
	if base <= EPSILON:
		return 0.0
	var kind := str(building["kind"])
	if kind == "solar" and layer == "power" and is_night:
		return 0.0
	# Producers with no utility demand (solar in daylight, reactor) are unconditional.
	if not _has_any_demand(data):
		return base
	return base if is_active else 0.0


static func _recycle_production(building: Dictionary, data: Dictionary,
		layer: String, is_active: bool) -> float:
	if not is_active or not is_operational(building) or is_isolated(building):
		return 0.0
	var use_amount := float(data.get(layer + "_use", 0.0))
	if use_amount <= EPSILON:
		return 0.0
	var rate := clampf(float(data.get(layer + "_recycle", 0.0)), 0.0, 0.95)
	return use_amount * rate


static func _stored_amount(building: Dictionary, data: Dictionary, layer: String) -> float:
	var capacity := float(data.get(layer + "_storage", 0.0))
	if capacity <= EPSILON:
		return 0.0
	var stored_dict: Variant = building.get("stored", {})
	if stored_dict is Dictionary:
		return clampf(float(stored_dict.get(layer, 0.0)), 0.0, capacity)
	return 0.0


static func _evaluate_layer_component(comp_cells: Array[Vector2i], layer: String,
		buildings: Dictionary, catalog: Dictionary, prev_active: Dictionary,
		is_night: bool, reserve_policy: String, reserve_floor: float) -> Dictionary:
	var gen_supply := 0.0
	var recycle_supply := 0.0
	var total_demand := 0.0
	var storage_capacity := 0.0
	var storage_stored := 0.0
	var max_discharge := 0.0
	var max_charge := 0.0
	var max_loss := 0.0
	var transport_cap := -1.0
	var consumers: Array[Dictionary] = []

	for cell in comp_cells:
		var building: Dictionary = buildings[cell]
		if not is_operational(building) or is_isolated(building):
			continue
		var data := _building_def(building, catalog)
		var was_active := bool(prev_active.get(cell, false))
		gen_supply += _raw_production(building, data, layer, is_night, was_active)
		recycle_supply += _recycle_production(building, data, layer, was_active)

		var cap := float(data.get(layer + "_storage", 0.0))
		if cap > EPSILON:
			storage_capacity += cap
			var cur_stored := _stored_amount(building, data, layer)
			storage_stored += cur_stored
			var d_rate := float(data.get(layer + "_discharge_rate", cap))
			var c_rate := float(data.get(layer + "_charge_rate", cap))
			max_discharge += minf(cur_stored, maxf(0.0, d_rate))
			max_charge += minf(maxf(0.0, cap - cur_stored), maxf(0.0, c_rate))

		var loss := clampf(float(data.get(layer + "_loss", 0.0)), 0.0, 0.95)
		if loss > max_loss:
			max_loss = loss

		var node_cap := float(data.get(layer + "_capacity", 0.0))
		if node_cap > EPSILON:
			transport_cap = node_cap if transport_cap < 0.0 else minf(transport_cap, node_cap)

		var demand := float(data.get(layer + "_use", 0.0))
		if demand > EPSILON:
			total_demand += demand
			consumers.append({
				"cell": cell,
				"demand": demand,
				"priority": building_priority(building, data),
			})

	# Apply transport losses and bottleneck capacity caps (never creates resources).
	var gross_generation := gen_supply + recycle_supply
	var effective_generation := gross_generation * (1.0 - max_loss)
	if transport_cap >= 0.0:
		effective_generation = minf(effective_generation, transport_cap)

	var effective_max_discharge := max_discharge * (1.0 - max_loss)
	if transport_cap >= 0.0:
		effective_max_discharge = minf(effective_max_discharge, maxf(0.0, transport_cap - effective_generation))

	# Reserve policy: under protect_essential, keep reserve_floor fraction for priority <= HABITAT.
	var essential_floor := 0.0
	if reserve_policy == RESERVE_POLICY_PROTECT_ESSENTIAL and storage_capacity > EPSILON:
		essential_floor = storage_capacity * clampf(reserve_floor, 0.0, 1.0)
	var discretionary_pool := maxf(0.0, storage_stored - essential_floor)
	var discretionary_discharge_cap := minf(effective_max_discharge, discretionary_pool * (1.0 - max_loss))

	# Sort consumers strictly by (priority, cell.x, cell.y) for deterministic load shedding.
	consumers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		return ca.x < cb.x if ca.x != cb.x else ca.y < cb.y
	)

	var remaining_gen := effective_generation
	var discharge_used := 0.0
	var demand_served := 0.0
	var served: Dictionary = {}
	var shed: Array[Vector2i] = []

	for entry in consumers:
		var cell: Vector2i = entry["cell"]
		var need: float = float(entry["demand"])
		var prio: int = int(entry["priority"])
		var avail_discharge := (
			maxf(0.0, effective_max_discharge - discharge_used)
			if prio <= PRIORITY_HABITAT
			else maxf(0.0, discretionary_discharge_cap - discharge_used)
		)
		if remaining_gen + avail_discharge + EPSILON >= need:
			var from_gen := minf(remaining_gen, need)
			var from_storage := maxf(0.0, need - from_gen)
			remaining_gen = maxf(0.0, remaining_gen - from_gen)
			discharge_used += from_storage
			demand_served += need
			served[cell] = true
		else:
			served[cell] = false
			shed.append(cell)

	# Raw storage deduction accounts for transport loss so conservation holds.
	var raw_discharge := (
		discharge_used / (1.0 - max_loss) if max_loss < 0.95 and discharge_used > EPSILON else discharge_used
	)
	raw_discharge = minf(raw_discharge, storage_stored)

	var surplus_gen := maxf(0.0, remaining_gen)
	var charge_planned := minf(surplus_gen, max_charge)
	var net_flow := charge_planned - raw_discharge
	var effective_supply := effective_generation + discharge_used
	var reserve_days := -1.0
	if raw_discharge > EPSILON:
		reserve_days = storage_stored / raw_discharge
	elif not shed.is_empty():
		reserve_days = 0.0

	return {
		"layer": layer,
		"cells": comp_cells,
		"generation": effective_generation,
		"supply": effective_supply,
		"demand": total_demand,
		"demand_served": demand_served,
		"served": served,
		"shed": shed,
		"storage_stored": storage_stored,
		"storage_capacity": storage_capacity,
		"charge_planned": charge_planned,
		"discharge_used": raw_discharge,
		"net_flow": net_flow,
		"reserve_days": reserve_days,
		"loss_rate": max_loss,
		"transport_cap": transport_cap,
	}


static func _snapshot_signature(active_map: Dictionary, sorted_cells: Array[Vector2i]) -> String:
	var bits := PackedStringArray()
	for cell in sorted_cells:
		bits.append("1" if bool(active_map.get(cell, false)) else "0")
	return "".join(bits)


static func evaluate(buildings: Dictionary, is_night: bool,
		catalog: Dictionary = BuildingCatalog.DATA,
		reserve_policy: String = RESERVE_POLICY_PROTECT_ESSENTIAL,
		reserve_floor: float = 0.25) -> Dictionary:
	var sorted_cells := _sorted_cells(buildings)
	var layer_graph := build_layer_components(buildings, catalog)

	# Initial conservative snapshot: only unconditional, operational, non-isolated
	# generators/infrastructure start active; dependent producers start inactive.
	var active_map: Dictionary = {}
	for cell in sorted_cells:
		var b: Dictionary = buildings[cell]
		var d := _building_def(b, catalog)
		var kind := str(b["kind"])
		var start_on := (
			is_operational(b)
			and not is_isolated(b)
			and not _has_any_demand(d)
			and not (kind == "solar" and is_night)
		)
		active_map[cell] = start_on

	var seen_states: Dictionary = {}
	var history: Array[Dictionary] = []
	var layer_results: Dictionary = {}
	var iterations := 0
	var converged := false

	for step in range(MAX_ITERATIONS):
		iterations = step + 1
		var sig := _snapshot_signature(active_map, sorted_cells)
		seen_states[sig] = history.size()
		history.append(active_map.duplicate())

		layer_results = {}
		for layer in LAYERS:
			var comp_evals: Array[Dictionary] = []
			for comp: Dictionary in layer_graph[layer]["components"]:
				comp_evals.append(_evaluate_layer_component(
					comp["cells"], layer, buildings, catalog, active_map,
					is_night, reserve_policy, reserve_floor
				))
			layer_results[layer] = comp_evals

		var next_active: Dictionary = {}
		for cell in sorted_cells:
			var b: Dictionary = buildings[cell]
			var d := _building_def(b, catalog)
			if not is_operational(b) or is_isolated(b):
				next_active[cell] = false
				continue
			var kind := str(b["kind"])
			if kind == "solar" and is_night:
				next_active[cell] = false
				continue
			var ok := true
			for layer in LAYERS:
				var need := float(d.get(layer + "_use", 0.0))
				if need <= EPSILON:
					continue
				if not layer_graph[layer]["cell_to_component"].has(cell):
					ok = false
					break
				var comp_id: int = int(layer_graph[layer]["cell_to_component"][cell])
				var comp_eval: Dictionary = layer_results[layer][comp_id]
				if not bool(comp_eval["served"].get(cell, false)):
					ok = false
					break
			next_active[cell] = ok

		var next_sig := _snapshot_signature(next_active, sorted_cells)
		if next_sig == sig:
			active_map = next_active
			converged = true
			break
		if seen_states.has(next_sig):
			# Oscillation cycle detected: converge deterministically to the
			# conservative intersection of all states in the cycle.
			var cycle_start: int = int(seen_states[next_sig])
			var resolved := next_active.duplicate()
			for idx in range(cycle_start, history.size()):
				var state: Dictionary = history[idx]
				for cell in sorted_cells:
					resolved[cell] = bool(resolved[cell]) and bool(state[cell])
			active_map = resolved
			# Re-evaluate layer results once against the resolved snapshot.
			layer_results = {}
			for layer in LAYERS:
				var comp_evals: Array[Dictionary] = []
				for comp: Dictionary in layer_graph[layer]["components"]:
					comp_evals.append(_evaluate_layer_component(
						comp["cells"], layer, buildings, catalog, active_map,
						is_night, reserve_policy, reserve_floor
					))
				layer_results[layer] = comp_evals
			converged = true
			break
		active_map = next_active

	# Build per-building status reasons and union network summaries.
	var status_reasons: Dictionary = {}
	for cell in sorted_cells:
		status_reasons[cell] = _diagnose_building(
			cell, buildings, catalog, layer_graph, layer_results, active_map, is_night
		)

	var union_groups := _build_union_components(buildings, catalog)
	var networks: Array[Dictionary] = []
	var cell_to_network: Dictionary = {}
	for group_idx in range(union_groups.size()):
		var cells: Array[Vector2i] = union_groups[group_idx]
		for c in cells:
			cell_to_network[c] = group_idx
		networks.append(_summarize_union_network(
			cells, buildings, catalog, layer_graph, layer_results,
			active_map, status_reasons, is_night, iterations, converged
		))

	return {
		"active": active_map,
		"status_reasons": status_reasons,
		"layer_graph": layer_graph,
		"layer_results": layer_results,
		"networks": networks,
		"cell_to_network": cell_to_network,
		"iterations": iterations,
		"converged": converged,
	}


static func apply_storage_step(buildings: Dictionary, evaluation: Dictionary,
		elapsed_days: float = 1.0,
		catalog: Dictionary = BuildingCatalog.DATA) -> bool:
	if elapsed_days <= EPSILON:
		return false
	var changed_any := false
	var layer_results: Dictionary = evaluation.get("layer_results", {})
	for layer in LAYERS:
		var comp_list: Array = layer_results.get(layer, [])
		for comp: Dictionary in comp_list:
			var charge_total := float(comp.get("charge_planned", 0.0)) * elapsed_days
			var discharge_total := float(comp.get("discharge_used", 0.0)) * elapsed_days
			var cells: Array[Vector2i] = comp.get("cells", [])
			if charge_total > EPSILON:
				var remaining := charge_total
				for cell in cells:
					if remaining <= EPSILON or not buildings.has(cell):
						break
					var b: Dictionary = buildings[cell]
					if not is_operational(b) or is_isolated(b):
						continue
					var d := _building_def(b, catalog)
					var cap := float(d.get(layer + "_storage", 0.0))
					if cap <= EPSILON:
						continue
					var c_rate := float(d.get(layer + "_charge_rate", cap)) * elapsed_days
					if not b.has("stored") or not (b["stored"] is Dictionary):
						b["stored"] = {}
					var cur := clampf(float(b["stored"].get(layer, 0.0)), 0.0, cap)
					var add := minf(remaining, minf(c_rate, maxf(0.0, cap - cur)))
					if add > EPSILON:
						b["stored"][layer] = cur + add
						remaining = maxf(0.0, remaining - add)
						changed_any = true
			if discharge_total > EPSILON:
				var remaining := discharge_total
				for cell in cells:
					if remaining <= EPSILON or not buildings.has(cell):
						break
					var b: Dictionary = buildings[cell]
					if not is_operational(b) or is_isolated(b):
						continue
					var d := _building_def(b, catalog)
					var cap := float(d.get(layer + "_storage", 0.0))
					if cap <= EPSILON:
						continue
					var d_rate := float(d.get(layer + "_discharge_rate", cap)) * elapsed_days
					if not b.has("stored") or not (b["stored"] is Dictionary):
						b["stored"] = {}
					var cur := clampf(float(b["stored"].get(layer, 0.0)), 0.0, cap)
					var take := minf(remaining, minf(d_rate, cur))
					if take > EPSILON:
						b["stored"][layer] = maxf(0.0, cur - take)
						remaining = maxf(0.0, remaining - take)
						changed_any = true
	return changed_any


static func _diagnose_building(cell: Vector2i, buildings: Dictionary,
		catalog: Dictionary, layer_graph: Dictionary, layer_results: Dictionary,
		active_map: Dictionary, is_night: bool) -> String:
	var b: Dictionary = buildings[cell]
	if float(b.get("build_progress", 1.0)) < 1.0:
		return "Under construction"
	var cond := str(b.get("condition", "operational"))
	if cond == "damaged":
		return "Damaged (offline)"
	if cond == "repairing":
		return "Under repair"
	if is_isolated(b):
		return "Isolated from utility network"
	if str(b["kind"]) == "solar" and is_night:
		return "Offline: lunar night (no sunlight)"
	if bool(active_map.get(cell, false)):
		return "Operational"
	var d := _building_def(b, catalog)
	var missing_layers: PackedStringArray = []
	for layer in LAYERS:
		if float(d.get(layer + "_use", 0.0)) <= EPSILON:
			continue
		if not layer_graph[layer]["cell_to_component"].has(cell):
			missing_layers.append(layer.capitalize())
			continue
		var comp_id: int = int(layer_graph[layer]["cell_to_component"][cell])
		var comp_eval: Dictionary = layer_results[layer][comp_id]
		if not bool(comp_eval["served"].get(cell, false)):
			missing_layers.append(layer.capitalize())
	if missing_layers.is_empty():
		return "Offline"
	var prio := building_priority(b, d)
	if prio >= PRIORITY_PRODUCTION:
		return "Shed (low priority: %s shortage)" % ", ".join(missing_layers)
	return "Shortage: %s" % ", ".join(missing_layers)


static func _summarize_union_network(cells: Array[Vector2i], buildings: Dictionary,
		catalog: Dictionary, layer_graph: Dictionary, layer_results: Dictionary,
		active_map: Dictionary, status_reasons: Dictionary, is_night: bool,
		iterations: int, converged: bool) -> Dictionary:
	var supply := {"power": 0.0, "water": 0.0, "oxygen": 0.0, "heat": 0.0}
	var demand := {"power": 0.0, "water": 0.0, "oxygen": 0.0, "heat": 0.0}
	var storage := {}
	var reserve_days := {}
	var layers_summary := {}
	var shortages: Array[String] = []
	var shed_seen: Dictionary = {}
	var shed_cells: Array[Vector2i] = []

	for layer in LAYERS:
		var comp_ids: Dictionary = {}
		for cell in cells:
			if layer_graph[layer]["cell_to_component"].has(cell):
				comp_ids[int(layer_graph[layer]["cell_to_component"][cell])] = true
		var stored_sum := 0.0
		var cap_sum := 0.0
		var net_flow_sum := 0.0
		var discharge_sum := 0.0
		var layer_short := false
		var min_reserve := -1.0
		for comp_id: int in comp_ids:
			var comp_eval: Dictionary = layer_results[layer][comp_id]
			supply[layer] += float(comp_eval["supply"])
			demand[layer] += float(comp_eval["demand"])
			stored_sum += float(comp_eval["storage_stored"])
			cap_sum += float(comp_eval["storage_capacity"])
			net_flow_sum += float(comp_eval["net_flow"])
			discharge_sum += float(comp_eval["discharge_used"])
			var comp_shed: Array = comp_eval["shed"]
			if not comp_shed.is_empty() or float(comp_eval["supply"]) + EPSILON < float(comp_eval["demand"]):
				layer_short = true
			for sc: Vector2i in comp_shed:
				if not shed_seen.has(sc):
					shed_seen[sc] = true
					shed_cells.append(sc)
			var rd := float(comp_eval["reserve_days"])
			if rd >= 0.0:
				min_reserve = rd if min_reserve < 0.0 else minf(min_reserve, rd)
		if layer_short:
			shortages.append(layer.capitalize())
		storage[layer] = {
			"stored": stored_sum,
			"capacity": cap_sum,
			"net_flow": net_flow_sum,
			"discharge_used": discharge_sum,
		}
		reserve_days[layer] = min_reserve
		layers_summary[layer] = {
			"supply": supply[layer],
			"demand": demand[layer],
			"shortage": layer_short,
			"reserve_days": min_reserve,
			"component_count": comp_ids.size(),
		}

	_sort_cells_in_place(shed_cells)
	var causes := _trace_causes(cells, buildings, catalog, supply, demand, shortages, active_map, is_night)
	var supported := shortages.is_empty()
	return {
		"cells": cells,
		"supply": supply,
		"demand": demand,
		"supported": supported,
		"shortages": shortages,
		"storage": storage,
		"reserve_days": reserve_days,
		"layers": layers_summary,
		"shed_cells": shed_cells,
		"causes": causes,
		"status_reasons": status_reasons,
		"iterations": iterations,
		"converged": converged,
	}


static func _trace_causes(cells: Array[Vector2i], buildings: Dictionary,
		catalog: Dictionary, supply: Dictionary, demand: Dictionary,
		shortages: Array[String], active_map: Dictionary, is_night: bool) -> Array[String]:
	var causes: Array[String] = []
	if shortages.is_empty():
		return causes

	var has_solar := false
	var damaged_power := false
	var building_power := false
	var has_ice := false
	var ice_unpowered := false
	var has_oxygen := false
	var oxygen_blocked_by: PackedStringArray = []

	for cell in cells:
		var b: Dictionary = buildings[cell]
		var kind := str(b["kind"])
		var d := _building_def(b, catalog)
		if float(d.get("power", 0.0)) > EPSILON:
			if kind == "solar":
				has_solar = true
			if str(b.get("condition", "operational")) != "operational":
				damaged_power = true
			elif float(b.get("build_progress", 1.0)) < 1.0:
				building_power = true
		if kind == "ice":
			has_ice = true
			if is_operational(b) and not is_isolated(b) and not bool(active_map.get(cell, false)):
				ice_unpowered = true
		if kind == "oxygen":
			has_oxygen = true
			if is_operational(b) and not is_isolated(b) and not bool(active_map.get(cell, false)):
				if "Power" in shortages and not ("Power" in oxygen_blocked_by):
					oxygen_blocked_by.append("Power")
				if "Water" in shortages and not ("Water" in oxygen_blocked_by):
					oxygen_blocked_by.append("Water")

	if "Power" in shortages:
		if has_solar and is_night:
			causes.append("Power shortage: solar arrays offline during lunar night.")
		elif damaged_power:
			causes.append("Power shortage: generator damaged or under repair.")
		elif building_power:
			causes.append("Power shortage: generator still under construction.")
		else:
			causes.append("Power shortage: demand (%.0f) exceeds local supply (%.0f)." % [
				float(demand["power"]), float(supply["power"])
			])

	if "Water" in shortages:
		if ice_unpowered and "Power" in shortages:
			causes.append("Water shortage: caused by upstream Power shortage (Ice extractor offline).")
		elif not has_ice:
			causes.append("Water shortage: no operational Ice extractor connected.")
		else:
			causes.append("Water shortage: demand (%.0f) exceeds local supply (%.0f)." % [
				float(demand["water"]), float(supply["water"])
			])

	if "Oxygen" in shortages:
		if has_oxygen and not oxygen_blocked_by.is_empty():
			causes.append("Oxygen shortage: caused by upstream %s shortage (Life support offline)." % [
				" & ".join(oxygen_blocked_by)
			])
		elif not has_oxygen:
			causes.append("Oxygen shortage: no operational Life support connected.")
		else:
			causes.append("Oxygen shortage: demand (%.0f) exceeds local supply (%.0f)." % [
				float(demand["oxygen"]), float(supply["oxygen"])
			])

	if "Heat" in shortages:
		if has_oxygen and not oxygen_blocked_by.is_empty():
			causes.append("Heat shortage: caused by upstream %s shortage (Life support offline)." % [
				" & ".join(oxygen_blocked_by)
			])
		else:
			causes.append("Heat shortage: demand (%.0f) exceeds local supply (%.0f)." % [
				float(demand["heat"]), float(supply["heat"])
			])

	return causes
