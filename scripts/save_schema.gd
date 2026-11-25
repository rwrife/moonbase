class_name SaveSchema
extends RefCounted

## Versioned data-only save schema, validation, and migration registry.
## All serialized values are plain JSON-compatible primitives (Dictionary, Array,
## String, int, float, bool); no scene nodes or engine objects are serialized.

const FORMAT_ID := "selene_frontier_save"
const CURRENT_VERSION := 2
const MIN_SUPPORTED_VERSION := 1


static func wrap_envelope(sim_state: Dictionary, slot_kind: String,
		saved_at_unix: int = -1) -> Dictionary:
	var timestamp := saved_at_unix if saved_at_unix >= 0 else int(Time.get_unix_time_from_system())
	var time_sec: Dictionary = sim_state.get("time", {})
	var econ_sec: Dictionary = sim_state.get("economy", {})
	var res_sec: Dictionary = sim_state.get("resources", {})
	var scen_sec: Dictionary = sim_state.get("scenario", {})
	var buildings_list: Array = sim_state.get("buildings", [])
	return {
		"format": FORMAT_ID,
		"schema_version": CURRENT_VERSION,
		"saved_at_unix": timestamp,
		"slot_kind": slot_kind,
		"colony_id": str(sim_state.get("colony_id", "")),
		"summary": {
			"day": int(time_sec.get("day", 1)),
			"credits": float(econ_sec.get("credits", 0.0)),
			"supplies": float(res_sec.get("supplies", 0.0)),
			"buildings": buildings_list.size(),
			"charter_complete": bool(scen_sec.get("charter_complete", false)),
		},
		"simulation": sim_state,
	}


static func unwrap_and_validate(raw_data: Variant, blocked_map: Dictionary = {}) -> Dictionary:
	if not (raw_data is Dictionary):
		return _fail("invalid_schema", "Save data root must be a JSON object.")
	var root: Dictionary = raw_data
	var is_envelope := root.has("simulation") or root.has("format") or root.has("schema_version")
	var saved_at_unix := 0
	var slot_kind := "manual"
	var sim_raw: Variant = root

	if is_envelope:
		if not (root.get("format") is String) or str(root["format"]) != FORMAT_ID:
			return _fail("invalid_schema",
				"Unrecognized save file format; expected '%s'." % FORMAT_ID)
		if not root.has("schema_version"):
			return _fail("invalid_schema", "Save envelope is missing 'schema_version'.")
		var env_ver_check := _require_whole_int(root["schema_version"], "schema_version")
		if not env_ver_check["ok"]:
			return env_ver_check
		var env_version: int = env_ver_check["value"]
		if env_version > CURRENT_VERSION:
			return _fail("unsupported_version",
				"Save version v%d is newer than this build supports (v%d). The file was preserved untouched." % [
					env_version, CURRENT_VERSION
				])
		if env_version < MIN_SUPPORTED_VERSION:
			return _fail("unsupported_version",
				"Save version v%d is unsupported (minimum v%d). The file was preserved untouched." % [
					env_version, MIN_SUPPORTED_VERSION
				])
		if not root.has("simulation") or not (root["simulation"] is Dictionary):
			return _fail("invalid_schema", "Save envelope is missing a valid 'simulation' object.")
		if root.has("saved_at_unix"):
			var ts_check := _require_whole_int(root["saved_at_unix"], "saved_at_unix")
			if not ts_check["ok"]:
				return ts_check
			saved_at_unix = int(ts_check["value"])
		if root.has("slot_kind"):
			if not (root["slot_kind"] is String):
				return _fail("invalid_schema", "Field 'slot_kind' must be a string.")
			slot_kind = str(root["slot_kind"])
		sim_raw = root["simulation"]

	var sim_result := migrate_and_validate(sim_raw, blocked_map)
	if not sim_result["ok"]:
		return sim_result
	var state: Dictionary = sim_result["state"]
	var time_sec: Dictionary = state["time"]
	var econ_sec: Dictionary = state["economy"]
	var res_sec: Dictionary = state["resources"]
	var scen_sec: Dictionary = state["scenario"]
	return {
		"ok": true,
		"error_code": "",
		"error": "",
		"state": state,
		"migrated_from": sim_result["migrated_from"],
		"saved_at_unix": saved_at_unix,
		"slot_kind": slot_kind,
		"colony_id": str(state["colony_id"]),
		"summary": {
			"day": int(time_sec["day"]),
			"credits": float(econ_sec["credits"]),
			"supplies": float(res_sec["supplies"]),
			"buildings": (state["buildings"] as Array).size(),
			"charter_complete": bool(scen_sec["charter_complete"]),
		},
	}


static func migrate_and_validate(raw_state: Variant, blocked_map: Dictionary = {}) -> Dictionary:
	if not (raw_state is Dictionary):
		return _fail("invalid_schema", "Simulation state must be a JSON object.")
	var state: Dictionary = raw_state
	if not state.has("version"):
		return _fail("invalid_schema", "Simulation state is missing required 'version' field.")
	var ver_check := _require_whole_int(state["version"], "version")
	if not ver_check["ok"]:
		return ver_check
	var version: int = ver_check["value"]
	if version > CURRENT_VERSION:
		return _fail("unsupported_version",
			"Save version v%d is newer than this build supports (v%d). The file was preserved untouched." % [
				version, CURRENT_VERSION
			])
	if version < MIN_SUPPORTED_VERSION:
		return _fail("unsupported_version",
			"Save version v%d is unsupported (minimum v%d). The file was preserved untouched." % [
				version, MIN_SUPPORTED_VERSION
			])

	var working: Dictionary = state.duplicate(true)
	var original_version := version
	# Sequential migration chain so future simulation systems append vN -> v(N+1).
	while version < CURRENT_VERSION:
		var step: Dictionary
		match version:
			1:
				step = _migrate_v1_to_v2(working)
			_:
				return _fail("unsupported_version",
					"No migration path registered from save version v%d." % version)
		if not step["ok"]:
			return step
		working = step["state"]
		version = int(working["version"])

	var validated := _validate_v2(working, blocked_map)
	if not validated["ok"]:
		return validated
	validated["migrated_from"] = original_version if original_version != CURRENT_VERSION else 0
	return validated


static func _migrate_v1_to_v2(v1: Dictionary) -> Dictionary:
	for required_key in ["day", "credits", "buildings", "graded"]:
		if not v1.has(required_key):
			return _fail("invalid_schema",
				"Legacy v1 save is missing required field '%s'." % required_key)
	var site_seed := ColonySimulation.DEFAULT_SITE_SEED
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	var migrated_colony_id := "legacy-v1-%d-%d" % [site_seed, int(v1.get("next_id", 1))]
	if v1.has("colony_id") and v1["colony_id"] is String and not str(v1["colony_id"]).is_empty():
		migrated_colony_id = str(v1["colony_id"])
	var v2 := {
		"version": 2,
		"colony_id": migrated_colony_id,
		"site_seed": site_seed,
		"rng": {
			"seed": str(rng.seed),
			"state": str(rng.state),
		},
		"time": {
			"day": v1.get("day"),
			"day_accumulator": v1.get("day_accumulator", 0.0),
		},
		"resources": {
			"supplies": v1.get("supplies", 0.0),
			"science": v1.get("science", 0.0),
			"exports": v1.get("exports", 0.0),
			"storage": {},
		},
		"economy": {
			"credits": v1.get("credits"),
			"deliveries_completed": v1.get("deliveries_completed", 0),
		},
		"crew": {
			"morale": v1.get("morale", 85.0),
			"health": 100.0,
			"roles": {},
		},
		"research": {
			"unlocked": [],
			"active": "",
			"progress": 0.0,
		},
		"scenario": {
			"id": ColonySimulation.DEFAULT_SCENARIO_ID,
			"charter_complete": v1.get("charter_complete", false),
			"flags": {},
			"last_report": v1.get("last_report", ""),
		},
		"next_id": v1.get("next_id", 1),
		"graded": v1.get("graded"),
		"buildings": v1.get("buildings"),
		"deliveries": v1.get("deliveries", []),
	}
	return {"ok": true, "state": v2}


static func _validate_v2(raw: Dictionary, blocked_map: Dictionary) -> Dictionary:
	var blocked := blocked_map if not blocked_map.is_empty() else SiteSurvey.blocked_cells(ColonySimulation.MAP_RADIUS)

	var colony_id_val: Variant = raw.get("colony_id")
	if not (colony_id_val is String) or str(colony_id_val).strip_edges().is_empty():
		return _fail("invalid_schema", "Field 'colony_id' must be a non-empty string.")
	var colony_id := str(colony_id_val)

	var seed_check := _require_whole_int(raw.get("site_seed"), "site_seed")
	if not seed_check["ok"]:
		return seed_check
	var site_seed: int = seed_check["value"]

	# RNG state
	if not (raw.get("rng") is Dictionary):
		return _fail("invalid_schema", "Section 'rng' must be an object.")
	var rng_sec: Dictionary = raw["rng"]
	var rng_seed_check := _require_int64_token(rng_sec.get("seed"), "rng.seed")
	if not rng_seed_check["ok"]:
		return rng_seed_check
	var rng_state_check := _require_int64_token(rng_sec.get("state"), "rng.state")
	if not rng_state_check["ok"]:
		return rng_state_check

	# Time
	if not (raw.get("time") is Dictionary):
		return _fail("invalid_schema", "Section 'time' must be an object.")
	var time_sec: Dictionary = raw["time"]
	var day_check := _require_whole_int(time_sec.get("day"), "time.day", 1)
	if not day_check["ok"]:
		return day_check
	var acc_check := _require_number(time_sec.get("day_accumulator"), "time.day_accumulator", 0.0, 1.0)
	if not acc_check["ok"]:
		return acc_check

	# Resources
	if not (raw.get("resources") is Dictionary):
		return _fail("invalid_schema", "Section 'resources' must be an object.")
	var res_sec: Dictionary = raw["resources"]
	var supplies_check := _require_number(res_sec.get("supplies"), "resources.supplies", 0.0)
	if not supplies_check["ok"]:
		return supplies_check
	var science_check := _require_number(res_sec.get("science"), "resources.science", 0.0)
	if not science_check["ok"]:
		return science_check
	var exports_check := _require_number(res_sec.get("exports"), "resources.exports", 0.0)
	if not exports_check["ok"]:
		return exports_check
	var storage_raw: Variant = res_sec.get("storage", {})
	if not (storage_raw is Dictionary):
		return _fail("invalid_schema", "Field 'resources.storage' must be an object.")
	var normalized_storage: Dictionary = {}
	for k in (storage_raw as Dictionary):
		if not (k is String):
			return _fail("invalid_schema", "Keys in 'resources.storage' must be strings.")
		var val_check := _require_number(storage_raw[k], "resources.storage.%s" % k, 0.0)
		if not val_check["ok"]:
			return val_check
		normalized_storage[str(k)] = float(val_check["value"])

	# Economy
	if not (raw.get("economy") is Dictionary):
		return _fail("invalid_schema", "Section 'economy' must be an object.")
	var econ_sec: Dictionary = raw["economy"]
	var credits_check := _require_number(econ_sec.get("credits"), "economy.credits")
	if not credits_check["ok"]:
		return credits_check
	var deliv_done_check := _require_whole_int(
		econ_sec.get("deliveries_completed"), "economy.deliveries_completed", 0
	)
	if not deliv_done_check["ok"]:
		return deliv_done_check

	# Crew
	if not (raw.get("crew") is Dictionary):
		return _fail("invalid_schema", "Section 'crew' must be an object.")
	var crew_sec: Dictionary = raw["crew"]
	var morale_check := _require_number(crew_sec.get("morale"), "crew.morale", 0.0, 100.0)
	if not morale_check["ok"]:
		return morale_check
	var health_check := _require_number(crew_sec.get("health", 100.0), "crew.health", 0.0, 100.0)
	if not health_check["ok"]:
		return health_check
	var roles_raw: Variant = crew_sec.get("roles", {})
	if not (roles_raw is Dictionary):
		return _fail("invalid_schema", "Field 'crew.roles' must be an object.")
	var normalized_roles: Dictionary = {}
	for k in (roles_raw as Dictionary):
		if not (k is String):
			return _fail("invalid_schema", "Keys in 'crew.roles' must be strings.")
		var role_count := _require_whole_int(roles_raw[k], "crew.roles.%s" % k, 0)
		if not role_count["ok"]:
			return role_count
		normalized_roles[str(k)] = int(role_count["value"])

	# Research
	if not (raw.get("research") is Dictionary):
		return _fail("invalid_schema", "Section 'research' must be an object.")
	var resch_sec: Dictionary = raw["research"]
	var unlocked_raw: Variant = resch_sec.get("unlocked", [])
	if not (unlocked_raw is Array):
		return _fail("invalid_schema", "Field 'research.unlocked' must be an array.")
	var normalized_unlocked: Array[String] = []
	for i in range((unlocked_raw as Array).size()):
		var item: Variant = unlocked_raw[i]
		if not (item is String) or str(item).is_empty():
			return _fail("invalid_schema", "Field 'research.unlocked[%d]' must be a non-empty string." % i)
		normalized_unlocked.append(str(item))
	var active_res: Variant = resch_sec.get("active", "")
	if not (active_res is String):
		return _fail("invalid_schema", "Field 'research.active' must be a string.")
	var res_prog_check := _require_number(resch_sec.get("progress", 0.0), "research.progress", 0.0)
	if not res_prog_check["ok"]:
		return res_prog_check

	# Scenario
	if not (raw.get("scenario") is Dictionary):
		return _fail("invalid_schema", "Section 'scenario' must be an object.")
	var scen_sec: Dictionary = raw["scenario"]
	var scen_id: Variant = scen_sec.get("id", ColonySimulation.DEFAULT_SCENARIO_ID)
	if not (scen_id is String) or str(scen_id).is_empty():
		return _fail("invalid_schema", "Field 'scenario.id' must be a non-empty string.")
	var charter_val: Variant = scen_sec.get("charter_complete")
	if not (charter_val is bool):
		return _fail("invalid_schema", "Field 'scenario.charter_complete' must be a boolean.")
	var flags_raw: Variant = scen_sec.get("flags", {})
	if not (flags_raw is Dictionary):
		return _fail("invalid_schema", "Field 'scenario.flags' must be an object.")
	var normalized_flags := _validate_json_dict(flags_raw, "scenario.flags")
	if not normalized_flags["ok"]:
		return normalized_flags
	var last_report_val: Variant = scen_sec.get("last_report", "")
	if not (last_report_val is String):
		return _fail("invalid_schema", "Field 'scenario.last_report' must be a string.")

	# next_id
	var next_id_check := _require_whole_int(raw.get("next_id"), "next_id", 1)
	if not next_id_check["ok"]:
		return next_id_check
	var next_id: int = next_id_check["value"]

	# Graded cells (preserving insertion order, rejecting out-of-bounds or blocked cells)
	var graded_raw: Variant = raw.get("graded")
	if not (graded_raw is Array):
		return _fail("invalid_schema", "Field 'graded' must be an array of [x, y] cells.")
	var normalized_graded: Array = []
	var seen_graded: Dictionary = {}
	for i in range((graded_raw as Array).size()):
		var cell_check := _require_cell(graded_raw[i], "graded[%d]" % i)
		if not cell_check["ok"]:
			return cell_check
		var cell: Vector2i = cell_check["value"]
		if blocked.has(cell):
			return _fail("invalid_schema",
				"Graded cell [%d, %d] overlaps an immovable %s." % [cell.x, cell.y, blocked[cell]])
		if not seen_graded.has(cell):
			seen_graded[cell] = true
			normalized_graded.append([cell.x, cell.y])

	# Buildings
	var buildings_raw: Variant = raw.get("buildings")
	if not (buildings_raw is Array):
		return _fail("invalid_schema", "Field 'buildings' must be an array.")
	var normalized_buildings: Array = []
	var seen_cells: Dictionary = {}
	var seen_ids: Dictionary = {}
	var max_building_id := 0
	for i in range((buildings_raw as Array).size()):
		var entry: Variant = buildings_raw[i]
		if not (entry is Dictionary):
			return _fail("invalid_schema", "Field 'buildings[%d]' must be an object." % i)
		var b: Dictionary = entry
		var cell_check := _require_cell(b.get("cell"), "buildings[%d].cell" % i)
		if not cell_check["ok"]:
			return cell_check
		var cell: Vector2i = cell_check["value"]
		if blocked.has(cell):
			return _fail("invalid_schema",
				"Building at [%d, %d] overlaps an immovable %s." % [cell.x, cell.y, blocked[cell]])
		if seen_cells.has(cell):
			return _fail("invalid_schema", "Duplicate building at cell [%d, %d]." % [cell.x, cell.y])
		var id_check := _require_whole_int(b.get("id"), "buildings[%d].id" % i, 1)
		if not id_check["ok"]:
			return id_check
		var id: int = id_check["value"]
		if seen_ids.has(id):
			return _fail("invalid_schema", "Duplicate building ID %d." % id)
		var kind_val: Variant = b.get("kind")
		if not (kind_val is String) or not BuildingCatalog.DATA.has(str(kind_val)):
			return _fail("invalid_schema",
				"Building #%d has unknown kind '%s'." % [id, str(kind_val)])
		var kind := str(kind_val)
		var bp_check := _require_number(
			b.get("build_progress", 1.0), "buildings[%d].build_progress" % i, 0.0, 1.0
		)
		if not bp_check["ok"]:
			return bp_check
		var cond_val: Variant = b.get("condition", ColonySimulation.CONDITION_OPERATIONAL)
		if not (cond_val is String) or not (str(cond_val) in ColonySimulation.VALID_CONDITIONS):
			return _fail("invalid_schema",
				"Building #%d has invalid condition '%s'." % [id, str(cond_val)])
		var rp_check := _require_number(
			b.get("repair_progress", 1.0), "buildings[%d].repair_progress" % i, 0.0, 1.0
		)
		if not rp_check["ok"]:
			return rp_check
		seen_cells[cell] = {"id": id, "kind": kind}
		seen_ids[id] = cell
		max_building_id = maxi(max_building_id, id)
		if not seen_graded.has(cell):
			seen_graded[cell] = true
			normalized_graded.append([cell.x, cell.y])
		normalized_buildings.append({
			"id": id,
			"cell": [cell.x, cell.y],
			"kind": kind,
			"build_progress": float(bp_check["value"]),
			"condition": str(cond_val),
			"repair_progress": float(rp_check["value"]),
		})

	if max_building_id >= next_id:
		return _fail("invalid_schema",
			"Field 'next_id' (%d) must exceed highest building ID (%d)." % [next_id, max_building_id])

	# Deliveries
	var deliveries_raw: Variant = raw.get("deliveries")
	if not (deliveries_raw is Array):
		return _fail("invalid_schema", "Field 'deliveries' must be an array.")
	var normalized_deliveries: Array = []
	var seen_delivery_ids: Dictionary = {}
	for i in range((deliveries_raw as Array).size()):
		var entry: Variant = deliveries_raw[i]
		if not (entry is Dictionary):
			return _fail("invalid_schema", "Field 'deliveries[%d]' must be an object." % i)
		var d: Dictionary = entry
		var bid_check := _require_whole_int(d.get("building_id"), "deliveries[%d].building_id" % i, 1)
		if not bid_check["ok"]:
			return bid_check
		var bid: int = bid_check["value"]
		if seen_delivery_ids.has(bid):
			return _fail("invalid_schema", "Duplicate delivery schedule for building #%d." % bid)
		var dcell_check := _require_cell(d.get("cell"), "deliveries[%d].cell" % i)
		if not dcell_check["ok"]:
			return dcell_check
		var dcell: Vector2i = dcell_check["value"]
		if not seen_cells.has(dcell) or int(seen_cells[dcell]["id"]) != bid:
			return _fail("invalid_schema",
				"Delivery schedule references missing building #%d at [%d, %d]." % [bid, dcell.x, dcell.y])
		if str(seen_cells[dcell]["kind"]) != "landing_pad":
			return _fail("invalid_schema",
				"Delivery schedule references non-landing-pad building #%d." % bid)
		var ct_check := _require_number(
			d.get("cycle_time"), "deliveries[%d].cycle_time" % i,
			0.0, ColonySimulation.SUPPLY_DELIVERY_INTERVAL
		)
		if not ct_check["ok"]:
			return ct_check
		var vid_check := _require_whole_int(d.get("visit_id"), "deliveries[%d].visit_id" % i, 1)
		if not vid_check["ok"]:
			return vid_check
		var cc_val: Variant = d.get("cargo_credited")
		if not (cc_val is bool):
			return _fail("invalid_schema", "Field 'deliveries[%d].cargo_credited' must be a boolean." % i)
		seen_delivery_ids[bid] = true
		normalized_deliveries.append({
			"building_id": bid,
			"cell": [dcell.x, dcell.y],
			"cycle_time": float(ct_check["value"]),
			"visit_id": int(vid_check["value"]),
			"cargo_credited": bool(cc_val),
		})

	return {
		"ok": true,
		"error_code": "",
		"error": "",
		"state": {
			"version": CURRENT_VERSION,
			"colony_id": colony_id,
			"site_seed": site_seed,
			"rng": {
				"seed": str(rng_seed_check["token"]),
				"state": str(rng_state_check["token"]),
			},
			"time": {
				"day": int(day_check["value"]),
				"day_accumulator": float(acc_check["value"]),
			},
			"resources": {
				"supplies": float(supplies_check["value"]),
				"science": float(science_check["value"]),
				"exports": float(exports_check["value"]),
				"storage": normalized_storage,
			},
			"economy": {
				"credits": float(credits_check["value"]),
				"deliveries_completed": int(deliv_done_check["value"]),
			},
			"crew": {
				"morale": float(morale_check["value"]),
				"health": float(health_check["value"]),
				"roles": normalized_roles,
			},
			"research": {
				"unlocked": normalized_unlocked,
				"active": str(active_res),
				"progress": float(res_prog_check["value"]),
			},
			"scenario": {
				"id": str(scen_id),
				"charter_complete": bool(charter_val),
				"flags": normalized_flags["value"],
				"last_report": str(last_report_val),
			},
			"next_id": next_id,
			"graded": normalized_graded,
			"buildings": normalized_buildings,
			"deliveries": normalized_deliveries,
		},
	}


static func _require_number(value: Variant, field: String,
		min_val: float = -INF, max_val: float = INF) -> Dictionary:
	if not (value is int or value is float):
		return _fail("invalid_schema", "Field '%s' must be a number." % field)
	var f := float(value)
	if is_nan(f) or is_inf(f):
		return _fail("invalid_schema", "Field '%s' must be a finite number." % field)
	if f < min_val or f > max_val:
		return _fail("invalid_schema",
			"Field '%s' value %.4f is outside allowed range." % [field, f])
	return {"ok": true, "value": f}


static func _require_whole_int(value: Variant, field: String,
		min_val: int = -9223372036854775807, max_val: int = 9223372036854775807) -> Dictionary:
	if value is int:
		var i: int = value
		if i < min_val or i > max_val:
			return _fail("invalid_schema",
				"Field '%s' value %d is outside allowed range." % [field, i])
		return {"ok": true, "value": i}
	if value is float:
		var f: float = value
		if is_nan(f) or is_inf(f) or floor(f) != f:
			return _fail("invalid_schema", "Field '%s' must be an integer." % field)
		if f < float(min_val) or f > float(max_val):
			return _fail("invalid_schema",
				"Field '%s' value %.0f is outside allowed range." % [field, f])
		return {"ok": true, "value": int(f)}
	return _fail("invalid_schema", "Field '%s' must be an integer." % field)


static func _require_int64_token(value: Variant, field: String) -> Dictionary:
	if value is String:
		var s := str(value).strip_edges()
		if s.is_empty() or not s.is_valid_int():
			return _fail("invalid_schema", "Field '%s' must be a valid 64-bit integer string." % field)
		return {"ok": true, "token": s, "value": s.to_int()}
	if value is int:
		return {"ok": true, "token": str(value), "value": int(value)}
	if value is float:
		var f: float = value
		if is_nan(f) or is_inf(f) or floor(f) != f:
			return _fail("invalid_schema", "Field '%s' must be an integer." % field)
		var iv := int(f)
		return {"ok": true, "token": str(iv), "value": iv}
	return _fail("invalid_schema", "Field '%s' must be a 64-bit integer string." % field)


static func _require_cell(value: Variant, field: String) -> Dictionary:
	if not (value is Array) or (value as Array).size() != 2:
		return _fail("invalid_schema", "Field '%s' must be a 2-element [x, y] coordinate." % field)
	var arr: Array = value
	var x_check := _require_whole_int(arr[0], field + "[0]",
		-ColonySimulation.MAP_RADIUS, ColonySimulation.MAP_RADIUS)
	if not x_check["ok"]:
		return x_check
	var y_check := _require_whole_int(arr[1], field + "[1]",
		-ColonySimulation.MAP_RADIUS, ColonySimulation.MAP_RADIUS)
	if not y_check["ok"]:
		return y_check
	return {"ok": true, "value": Vector2i(int(x_check["value"]), int(y_check["value"]))}


static func _validate_json_dict(value: Dictionary, field: String) -> Dictionary:
	var out: Dictionary = {}
	for k in value:
		if not (k is String):
			return _fail("invalid_schema", "Keys in '%s' must be strings." % field)
		var v: Variant = value[k]
		if v is bool or v is String or v is int:
			out[str(k)] = v
		elif v is float:
			if is_nan(v) or is_inf(v):
				return _fail("invalid_schema", "Non-finite value in '%s.%s'." % [field, k])
			if floor(v) == v and absf(v) <= 9007199254740991.0:
				out[str(k)] = int(v)
			else:
				out[str(k)] = v
		else:
			return _fail("invalid_schema",
				"Field '%s.%s' must be a primitive JSON value." % [field, k])
	return {"ok": true, "value": out}


static func _fail(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error_code": code,
		"error": message,
		"state": {},
		"migrated_from": 0,
	}
