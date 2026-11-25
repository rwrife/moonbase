extends SceneTree

var failures := 0


func _init() -> void:
	test_round_trip_and_determinism()
	test_v1_migration_fixtures()
	test_validation_and_preservation()
	test_atomic_writes_interruption_and_backups()
	test_storage_unavailable_and_quota_exceeded()
	test_colony_conflict_and_restart_policy()
	if failures == 0:
		print("PASS: versioned save schema, migration, validation, atomic writes, backups, storage faults and overwrite policy")
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _make_temp_dir(tag: String) -> String:
	var dir_path := OS.get_cache_dir().path_join(
		"selene_save_test_%s_%d_%d" % [tag, OS.get_process_id(), Time.get_ticks_usec()]
	)
	DirAccess.make_dir_recursive_absolute(dir_path)
	return dir_path


func _cleanup_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir():
			DirAccess.remove_absolute(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func _is_pure_json_data(value: Variant) -> bool:
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		for item in value:
			if not _is_pure_json_data(item):
				return false
		return true
	if value is Dictionary:
		for k in value:
			if not (k is String) or not _is_pure_json_data(value[k]):
				return false
		return true
	return false


func test_round_trip_and_determinism() -> void:
	var tmp_dir := _make_temp_dir("roundtrip")
	var store := ColonySaveStore.new(SaveStorageBackend.FileBackend.new(tmp_dir))

	var sim := ColonySimulation.new()
	sim.reset(4242, "colony-test-alpha")
	check(sim.place("reactor", Vector2i(0, 1)), "Place reactor")
	check(sim.place("lab", Vector2i(1, 1)), "Place lab")
	check(sim.place("mine", Vector2i(1, 0)), "Place mine")
	check(sim.place("landing_pad", Vector2i(3, -2)), "Place second landing pad")
	check(sim.bulldoze(Vector2i(5, 5)), "Bulldoze extra pad")
	check(sim.bulldoze(Vector2i(5, 4)), "Bulldoze adjacent pad to verify grading order")
	sim.set_building_build_progress(Vector2i(1, 1), 0.65)
	sim.set_building_condition(Vector2i(1, 0), ColonySimulation.CONDITION_REPAIRING, 0.35)
	sim.utility_storage = {"power": 120.5, "water": 45.0, "oxygen": 30.0}
	sim.crew_roles = {"engineer": 4, "scientist": 2, "medic": 2}
	sim.crew_health = 92.5
	sim.research_unlocked = ["thermal_blankets", "deep_drilling"]
	sim.research_active = "closed_loop_life_support"
	sim.research_progress = 14.25
	sim.scenario_flags = {"night_survived": true, "briefing_step": 3}

	# Advance time to a fractional day mid-delivery and advance RNG state.
	sim.advance(7.45)
	for i in range(17):
		sim.rng.randi()

	var exported := sim.export_state()
	check(_is_pure_json_data(exported), "Exported state must contain only pure JSON-compatible data")
	check(exported["version"] == SaveSchema.CURRENT_VERSION, "Export must use current schema version")

	var save_res := store.save_simulation(ColonySaveStore.SLOT_MANUAL, sim)
	check(save_res["ok"], "Manual save must succeed: " + str(save_res.get("error", "")))

	var loaded := ColonySimulation.new()
	var load_res := store.load_into_simulation(ColonySaveStore.SLOT_MANUAL, loaded)
	check(load_res["ok"], "Manual load must succeed: " + str(load_res.get("error", "")))
	check(int(load_res["migrated_from"]) == 0, "Current-version load must not report migration")

	# Verify exact state preservation across all sections.
	check(loaded.colony_id == sim.colony_id, "Colony ID must round-trip")
	check(loaded.site_seed == 4242, "Site seed must round-trip")
	check(loaded.rng.seed == sim.rng.seed and loaded.rng.state == sim.rng.state,
		"64-bit RNG seed and state must round-trip exactly")
	check(loaded.day == sim.day and is_equal_approx(loaded.day_accumulator, sim.day_accumulator),
		"Simulation time and fractional day_accumulator must round-trip")
	check(is_equal_approx(loaded.credits, sim.credits) and is_equal_approx(loaded.supplies, sim.supplies),
		"Economy and supplies must round-trip")
	check(loaded.deliveries_completed == sim.deliveries_completed, "Deliveries count must round-trip")
	check(is_equal_approx(loaded.morale, sim.morale) and is_equal_approx(loaded.crew_health, 92.5),
		"Crew morale and health must round-trip")
	check(loaded.crew_roles == sim.crew_roles, "Crew roles must round-trip")
	check(loaded.utility_storage == sim.utility_storage, "Utility storage must round-trip")
	check(loaded.research_unlocked == sim.research_unlocked
		and loaded.research_active == sim.research_active
		and is_equal_approx(loaded.research_progress, sim.research_progress),
		"Research state must round-trip")
	check(loaded.scenario_id == sim.scenario_id and loaded.scenario_flags == sim.scenario_flags,
		"Scenario flags must round-trip")
	check(loaded.graded.keys() == sim.graded.keys(), "Graded pad insertion order must round-trip")
	check(loaded.buildings == sim.buildings, "Buildings and structure states must round-trip")
	check(_deliveries_match(loaded.deliveries, sim.deliveries), "Delivery schedules must round-trip")
	check(loaded.next_id == sim.next_id, "next_id must round-trip")

	# Deterministic continuation: advance both simulations identically and draw RNG values.
	var rng_draws_a: Array[int] = []
	var rng_draws_b: Array[int] = []
	for step in range(40):
		sim.advance(0.63)
		loaded.advance(0.63)
		rng_draws_a.append(sim.rng.randi())
		rng_draws_b.append(loaded.rng.randi())

	check(rng_draws_a == rng_draws_b, "Restored RNG must produce identical deterministic continuation")
	check(sim.day == loaded.day and is_equal_approx(sim.day_accumulator, loaded.day_accumulator),
		"Continued time must match exactly")
	check(is_equal_approx(sim.credits, loaded.credits) and is_equal_approx(sim.supplies, loaded.supplies),
		"Continued economy and supplies must match exactly")
	check(is_equal_approx(sim.science, loaded.science) and is_equal_approx(sim.exports, loaded.exports),
		"Continued science and exports must match exactly")
	check(sim.buildings == loaded.buildings and sim.networks == loaded.networks
		and _deliveries_match(sim.deliveries, loaded.deliveries),
		"Continued buildings, networks and deliveries must match exactly")

	_cleanup_dir(tmp_dir)


func _deliveries_match(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for id in a:
		if not b.has(id):
			return false
		var da: Dictionary = a[id]
		var db: Dictionary = b[id]
		if (
			int(da["building_id"]) != int(db["building_id"])
			or da["cell"] != db["cell"]
			or str(da["phase"]) != str(db["phase"])
			or int(da["visit_id"]) != int(db["visit_id"])
			or bool(da["cargo_credited"]) != bool(db["cargo_credited"])
			or not is_equal_approx(float(da["cycle_time"]), float(db["cycle_time"]))
			or not is_equal_approx(float(da["phase_progress"]), float(db["phase_progress"]))
		):
			return false
	return true


func test_v1_migration_fixtures() -> void:
	var tmp_dir := _make_temp_dir("migrate_v1")
	var backend := SaveStorageBackend.FileBackend.new(tmp_dir)
	var store := ColonySaveStore.new(backend)

	# Authentic v1 save fixture (matching PR #26 schema before v2).
	var v1_fixture := {
		"version": 1,
		"day": 14,
		"day_accumulator": 0.25,
		"credits": 945.0,
		"supplies": 8.0,
		"deliveries_completed": 2,
		"morale": 89.5,
		"science": 11.0,
		"exports": 22.0,
		"charter_complete": false,
		"last_report": "Supply lander delivered 4 t supplies to Landing pad #5.",
		"next_id": 8,
		"graded": [[-3, 0], [-2, 0], [-1, 0], [0, 0], [0, -2], [0, 1], [1, 1]],
		"buildings": [
			{"cell": [-3, 0], "id": 1, "kind": "ice", "build_progress": 1.0, "condition": "operational", "repair_progress": 1.0},
			{"cell": [-2, 0], "id": 2, "kind": "oxygen", "build_progress": 1.0, "condition": "operational", "repair_progress": 1.0},
			{"cell": [-1, 0], "id": 3, "kind": "habitat", "build_progress": 1.0, "condition": "operational", "repair_progress": 1.0},
			{"cell": [0, 0], "id": 4, "kind": "solar", "build_progress": 1.0, "condition": "operational", "repair_progress": 1.0},
			{"cell": [0, -2], "id": 5, "kind": "landing_pad", "build_progress": 1.0, "condition": "operational", "repair_progress": 1.0},
			{"cell": [0, 1], "id": 6, "kind": "reactor", "build_progress": 1.0, "condition": "operational", "repair_progress": 1.0},
			{"cell": [1, 1], "id": 7, "kind": "lab", "build_progress": 0.5, "condition": "operational", "repair_progress": 1.0},
		],
		"deliveries": [
			{"building_id": 5, "cell": [0, -2], "cycle_time": 4.5, "visit_id": 3, "cargo_credited": false},
		],
	}
	var write_res := backend.write_text_atomic(
		ColonySaveStore.primary_key("manual"), JSON.stringify(v1_fixture, "\t"), "", false
	)
	check(write_res["ok"], "Write v1 fixture")

	var sim := ColonySimulation.new()
	var load_res := store.load_into_simulation(ColonySaveStore.SLOT_MANUAL, sim)
	check(load_res["ok"], "v1 save fixture must migrate cleanly: " + str(load_res.get("error", "")))
	check(int(load_res["migrated_from"]) == 1, "Result must report migration from v1")
	check(sim.day == 14 and is_equal_approx(sim.credits, 945.0) and is_equal_approx(sim.supplies, 8.0),
		"Migrated v1 resources and day must match fixture")
	check(sim.buildings.size() == 7 and is_equal_approx(sim.buildings[Vector2i(1, 1)]["build_progress"], 0.5),
		"Migrated v1 buildings and states must match fixture")
	check(sim.delivery_for_cell(Vector2i(0, -2))["phase"] == "descending",
		"Migrated v1 delivery schedule must preserve flight phase")
	check(not sim.colony_id.is_empty() and sim.site_seed == ColonySimulation.DEFAULT_SITE_SEED,
		"Migration must populate v2 colony_id and default site_seed")

	# Re-saving migrated colony upgrades file cleanly to v2.
	var resave := store.save_simulation(ColonySaveStore.SLOT_MANUAL, sim)
	check(resave["ok"], "Re-saving migrated colony must succeed")
	var reloaded := ColonySimulation.new()
	var reload_res := store.load_into_simulation(ColonySaveStore.SLOT_MANUAL, reloaded)
	check(reload_res["ok"] and int(reload_res["migrated_from"]) == 0,
		"Re-saved colony must now be native v2 without further migration")

	# Corrupt v1 fixture (missing required 'buildings') must fail explicitly without mutating live sim.
	var broken_v1 := {"version": 1, "day": 5, "credits": 100.0, "graded": []}
	var broken_res := sim.import_state_detailed(broken_v1)
	check(not broken_res["ok"] and broken_res["error_code"] == "invalid_schema",
		"Corrupt v1 fixture must be rejected with invalid_schema")
	check(sim.day == 14 and sim.buildings.size() == 7,
		"Failed v1 import must not mutate live simulation")

	_cleanup_dir(tmp_dir)


func test_validation_and_preservation() -> void:
	var tmp_dir := _make_temp_dir("validation")
	var backend := SaveStorageBackend.FileBackend.new(tmp_dir)
	var store := ColonySaveStore.new(backend)

	var live := ColonySimulation.new()
	live.place("reactor", Vector2i(0, 1))
	live.advance(3.0)
	var before_snapshot := live.export_state()

	# 1. Unsupported future version must fail loudly, preserve file, and resist accidental overwrite.
	var future_json := JSON.stringify({
		"format": SaveSchema.FORMAT_ID,
		"schema_version": 99,
		"simulation": {"version": 99}
	})
	var key := ColonySaveStore.primary_key("manual")
	backend.write_text_atomic(key, future_json, "", false)

	var load_future := store.load_into_simulation("manual", live)
	check(not load_future["ok"] and load_future["error_code"] == "unsupported_version",
		"Future save version must return unsupported_version")
	check(bool(load_future["preserved"]), "Future save version must report preserved=true")
	check(live.export_state() == before_snapshot, "Unsupported version load must not alter live simulation")
	check(backend.read_text(key)["text"] == future_json, "Unsupported future file must remain intact on disk")

	var blocked_save := store.save_simulation("manual", live, ColonySaveStore.OverwritePolicy.SAME_COLONY_ONLY)
	check(not blocked_save["ok"] and blocked_save["error_code"] == "unsupported_version_protected",
		"Saving over unsupported future save without ALLOW_ANY must be blocked")
	check(backend.read_text(key)["text"] == future_json,
		"Blocked save must leave unsupported future file intact on disk")

	# 2. Corrupt JSON must fail loudly and preserve raw file bytes.
	var corrupt_bytes := "{not valid json at all"
	backend.write_text_atomic(key, corrupt_bytes, "", false)
	var load_corrupt := store.load_into_simulation("manual", live)
	check(not load_corrupt["ok"] and load_corrupt["error_code"] == "corrupt_json",
		"Corrupt JSON must return corrupt_json")
	check(backend.read_text(key)["text"] == corrupt_bytes, "Corrupt save file must be preserved untouched")
	check(live.export_state() == before_snapshot, "Corrupt load must not alter live simulation")

	# 3. Schema/range/integrity violations must all fail without mutating live simulation.
	var valid_base := live.export_state()
	var blocked_cell: Vector2i = live.blocked.keys()[0]
	var bad_cases: Array = [
		["day < 1", func(s: Dictionary): s["time"]["day"] = 0],
		["day bool", func(s: Dictionary): s["time"]["day"] = true],
		["morale > 100", func(s: Dictionary): s["crew"]["morale"] = 125.0],
		["negative supplies", func(s: Dictionary): s["resources"]["supplies"] = -2.0],
		["unknown building kind", func(s: Dictionary): s["buildings"][0]["kind"] = "warp_core"],
		["invalid condition", func(s: Dictionary): s["buildings"][0]["condition"] = "melted"],
		["out of bounds cell", func(s: Dictionary): s["buildings"][0]["cell"] = [99, 0]],
		["building on blocked landmark", func(s: Dictionary): s["buildings"][0]["cell"] = [blocked_cell.x, blocked_cell.y]],
		["duplicate building cell", func(s: Dictionary): s["buildings"][1]["cell"] = s["buildings"][0]["cell"]],
		["duplicate building id", func(s: Dictionary): s["buildings"][1]["id"] = s["buildings"][0]["id"]],
		["next_id too small", func(s: Dictionary): s["next_id"] = 2],
		["orphan delivery", func(s: Dictionary): s["deliveries"].append({"building_id": 999, "cell": [2, 2], "cycle_time": 1.0, "visit_id": 1, "cargo_credited": false})],
		["invalid rng state", func(s: Dictionary): s["rng"]["state"] = "abc_not_int"],
		["empty colony_id", func(s: Dictionary): s["colony_id"] = "   "],
	]
	for item in bad_cases:
		var label: String = item[0]
		var mutator: Callable = item[1]
		var candidate := valid_base.duplicate(true)
		mutator.call(candidate)
		var res := live.import_state_detailed(candidate)
		check(not res["ok"] and res["error_code"] == "invalid_schema",
			"Invalid save case '%s' must fail validation (got %s)" % [label, str(res)])
		check(live.export_state() == before_snapshot,
			"Failed validation case '%s' must not mutate live simulation" % label)

	_cleanup_dir(tmp_dir)


func test_atomic_writes_interruption_and_backups() -> void:
	var tmp_dir := _make_temp_dir("atomic")
	var backend := SaveStorageBackend.FileBackend.new(tmp_dir)
	var store := ColonySaveStore.new(backend)

	var sim := ColonySimulation.new()
	sim.place("reactor", Vector2i(0, 1))
	sim.advance(4.0) # Day 5
	check(store.save_simulation("manual", sim)["ok"], "Initial save at Day 5 must succeed")

	sim.advance(5.0) # Day 10
	check(store.save_simulation("manual", sim)["ok"], "Second save at Day 10 must succeed and create Day 5 backup")
	check(backend.key_exists(ColonySaveStore.backup_key("manual")), "Backup file must exist after overwrite")

	# Simulate interrupted writes at all three stages while attempting to save Day 15.
	sim.advance(5.0) # Day 15
	for fault_stage in ["partial_tmp_write", "after_tmp_write", "before_rename"]:
		backend.simulate_fault = fault_stage
		var fail_res := store.save_simulation("manual", sim)
		backend.simulate_fault = ""
		check(not fail_res["ok"] and fail_res["error_code"] == "interrupted_write",
			"Fault '%s' must report interrupted_write" % fault_stage)
		var verify_sim := ColonySimulation.new()
		var verify_load := store.load_into_simulation("manual", verify_sim)
		check(verify_load["ok"] and verify_sim.day == 10,
			"Interrupted write '%s' must leave previous Day 10 save intact" % fault_stage)

	# Corrupt primary file externally; verify backup recovery works while preserving corrupt primary.
	var primary_path := backend.describe_location(ColonySaveStore.primary_key("manual"))
	var corrupt_content := "{truncated_mid_sector"
	var f := FileAccess.open(primary_path, FileAccess.WRITE)
	f.store_string(corrupt_content)
	f.flush()
	f.close()

	var recovered := ColonySimulation.new()
	var bad_load := store.load_into_simulation("manual", recovered)
	check(not bad_load["ok"] and bad_load["error_code"] == "corrupt_json",
		"Corrupted primary must fail with corrupt_json")
	check(bool(bad_load["backup_available"]), "Corrupted primary must advertise available backup")
	check(backend.read_text(ColonySaveStore.primary_key("manual"))["text"] == corrupt_content,
		"Failed load must preserve corrupted primary file")

	var bak_load := store.load_into_simulation("manual", recovered, true)
	check(bak_load["ok"] and recovered.day == 10 or (bak_load["ok"] and recovered.day == 5),
		"Explicit backup restore must recover a valid earlier snapshot")
	check(backend.read_text(ColonySaveStore.primary_key("manual"))["text"] == corrupt_content,
		"Restoring backup must still preserve corrupted primary file until user explicitly saves")

	# Forced overwrite over corrupt primary must NOT clobber the valid backup with corrupt bytes.
	var bak_before: String = str(backend.read_text(ColonySaveStore.backup_key("manual"))["text"])
	var forced := store.save_simulation("manual", sim, ColonySaveStore.OverwritePolicy.ALLOW_ANY)
	check(forced["ok"], "Explicit ALLOW_ANY overwrite over corrupt file must succeed")
	check(backend.read_text(ColonySaveStore.backup_key("manual"))["text"] == bak_before,
		"Overwriting corrupt primary must never copy corrupt bytes over a healthy backup")

	_cleanup_dir(tmp_dir)


func test_storage_unavailable_and_quota_exceeded() -> void:
	# 1. Missing save slot.
	var mem := SaveStorageBackend.MemoryBackend.new()
	var store := ColonySaveStore.new(mem)
	var sim := ColonySimulation.new()
	var missing_res := store.load_into_simulation("manual", sim)
	check(not missing_res["ok"] and missing_res["error_code"] == "missing",
		"Missing slot must return explicit missing error")

	# 2. Save once, then deny storage availability.
	sim.advance(3.0)
	check(store.save_simulation("manual", sim)["ok"], "Initial save to memory backend must succeed")
	mem.available = false
	var unavail_save := store.save_simulation("manual", sim)
	check(not unavail_save["ok"] and unavail_save["error_code"] == "storage_unavailable",
		"Unavailable storage must report storage_unavailable on save")
	var unavail_load := store.load_into_simulation("manual", sim)
	check(not unavail_load["ok"] and unavail_load["error_code"] == "storage_unavailable",
		"Unavailable storage must report storage_unavailable on load")
	mem.available = true

	# 3. Quota exceeded must fail explicitly and preserve the existing valid save.
	var existing_size := str(mem.store[ColonySaveStore.primary_key("manual")]).to_utf8_buffer().size()
	mem.quota_bytes = existing_size + 16 # Not enough room for primary + backup rotation.
	sim.advance(5.0)
	var quota_res := store.save_simulation("manual", sim)
	check(not quota_res["ok"] and quota_res["error_code"] == "quota_exceeded",
		"Exceeding quota must report quota_exceeded")
	mem.quota_bytes = -1
	var check_sim := ColonySimulation.new()
	var reload := store.load_into_simulation("manual", check_sim)
	check(reload["ok"] and check_sim.day == 4,
		"Quota failure must preserve the previous valid save untouched")


func test_colony_conflict_and_restart_policy() -> void:
	var mem := SaveStorageBackend.MemoryBackend.new()
	var store := ColonySaveStore.new(mem)

	# Colony A progresses to Day 11 and saves to manual + autosave.
	var sim := ColonySimulation.new()
	var colony_a_id := sim.colony_id
	sim.place("reactor", Vector2i(0, 1))
	sim.advance(10.0) # Day 11
	check(store.save_simulation(ColonySaveStore.SLOT_MANUAL, sim)["ok"], "Save Colony A manual")
	check(store.save_simulation(ColonySaveStore.SLOT_AUTOSAVE, sim)["ok"], "Save Colony A autosave")

	# Restart creates a brand-new colony_id and must not clobber Colony A.
	sim.reset()
	check(sim.colony_id != colony_a_id, "Restart must allocate a new colony_id")
	sim.advance(5.0) # Colony B Day 6

	var conflict_manual := store.save_simulation(ColonySaveStore.SLOT_MANUAL, sim)
	check(not conflict_manual["ok"] and conflict_manual["error_code"] == "colony_conflict",
		"New colony must not accidentally overwrite different colony's manual save")
	var conflict_auto := store.save_simulation(ColonySaveStore.SLOT_AUTOSAVE, sim)
	check(not conflict_auto["ok"] and conflict_auto["error_code"] == "colony_conflict",
		"New colony must not accidentally overwrite different colony's autosave")

	# Colony A must still be completely intact in both slots.
	var verify_a := ColonySimulation.new()
	check(store.load_into_simulation(ColonySaveStore.SLOT_MANUAL, verify_a)["ok"]
		and verify_a.colony_id == colony_a_id and verify_a.day == 11,
		"Colony A manual save must remain intact after blocked overwrite")
	var verify_a_auto := ColonySimulation.new()
	check(store.load_into_simulation(ColonySaveStore.SLOT_AUTOSAVE, verify_a_auto)["ok"]
		and verify_a_auto.colony_id == colony_a_id and verify_a_auto.day == 11,
		"Colony A autosave must remain intact after blocked overwrite")

	# Explicit ALLOW_DIFFERENT_COLONY replaces primary and keeps Colony A in .bak.
	var confirmed := store.save_simulation(
		ColonySaveStore.SLOT_MANUAL, sim, ColonySaveStore.OverwritePolicy.ALLOW_DIFFERENT_COLONY
	)
	check(confirmed["ok"], "Explicit overwrite policy must permit saving Colony B")
	var bak_a := ColonySimulation.new()
	check(store.load_into_simulation(ColonySaveStore.SLOT_MANUAL, bak_a, true)["ok"]
		and bak_a.colony_id == colony_a_id and bak_a.day == 11,
		"Confirmed overwrite must still rotate Colony A into backup")

	# Subsequent SAME_COLONY_ONLY saves for Colony B now succeed automatically.
	sim.advance(2.0)
	check(store.save_simulation(ColonySaveStore.SLOT_MANUAL, sim)["ok"],
		"Subsequent saves for Colony B must succeed under SAME_COLONY_ONLY")
