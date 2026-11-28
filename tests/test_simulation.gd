extends SceneTree

var failures := 0


func _init() -> void:
	test_placement()
	test_connections()
	test_standardized_connectors_and_power_lines()
	test_night_cascade()
	test_economy_and_charter()
	test_no_crew_production()
	test_determinism()
	test_grading_and_landmarks()
	test_landing_pad_deliveries()
	test_structure_states_and_serialization()
	if failures == 0:
		print("PASS: placement, standardized connectors, power lines, topology, cascades, economy, charter, determinism, grading, deliveries and states")
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func test_placement() -> void:
	var sim := ColonySimulation.new()
	var initial := sim.buildings.duplicate(true)
	var messages: Array[String] = []
	sim.notification.connect(func(message: String): messages.append(message))
	for entry in [
		["habitat", Vector2i(0, 0)],
		["solar", Vector2i(11, 0)],
		["ice", Vector2i(2, 2)],
		["unknown", Vector2i(2, 2)]
	]:
		check(not sim.place(entry[0], entry[1]), "Invalid placement must fail")
		check(sim.buildings == initial, "Rejected placement mutated buildings")
		check(sim.credits == 1800, "Rejected placement charged credits")
	check(messages.size() == 4, "Rejections must notify the player")
	sim.credits = 19
	check(not sim.place("tunnel", Vector2i(1, 0)), "Unaffordable placement must fail")
	check(sim.credits == 19, "Unaffordable placement mutated credits")
	sim.credits = 1800
	check(sim.place("ice", Vector2i(-4, 0)), "Ice deposit should allow extraction")
	check(sim.credits == 1600, "Construction must charge exactly once")
	check(sim.demolish(Vector2i(-4, 0)), "Demolition should succeed")
	check(sim.credits == 1650, "Demolition must refund 25 percent")


func test_connections() -> void:
	var sim := ColonySimulation.new()
	var base_networks := sim.networks.size()
	check(sim.safe_crew == 8, "Starter outpost must be supplied")
	check(sim.place("habitat", Vector2i(2, 0), 1), "Place isolated habitat oriented E-W")
	check(sim.networks.size() == base_networks + 1, "Separated cells must form distinct components")
	check(not sim.buildings[Vector2i(2, 0)]["active"], "Remote supply must not serve isolated habitat")
	check(sim.place("tunnel", Vector2i(1, 0)), "Bridge isolated habitat with connection tunnel")
	check(sim.networks.size() == base_networks and sim.safe_crew == 16,
		"Connection tunnel must merge service networks and restore service")
	check(sim.demolish(Vector2i(1, 0)), "Remove connection tunnel")
	check(sim.networks.size() == base_networks + 1 and sim.safe_crew == 8,
		"Removing bridge must split networks")
	check(sim.place("solar", Vector2i(3, 1)), "Place diagonal generator")
	check(sim.networks.size() == base_networks + 2, "Diagonal neighbors must not connect")
	var local: Dictionary = sim.networks[sim.buildings[Vector2i(2, 0)]["network"]]
	check(local["supply"]["power"] == 0, "Isolated component cannot borrow global surplus")
	check("Power" in local["shortages"], "Inspection must identify local shortage")


func test_standardized_connectors_and_power_lines() -> void:
	var sim := ColonySimulation.new()
	# Starter outpost: Ice(-3,0) <-> O2(-2,0) <-> Habitat(-1,0) <-> SupportHub(0,0) <-> Solar(0,1).
	var hub: Dictionary = sim.buildings[Vector2i(0, 0)]
	check(hub["kind"] == "support_hub", "Starter center cell must hold 4-Way adapter")
	check(int(hub["service_mask"]) == (BuildingCatalog.BIT_W | BuildingCatalog.BIT_S),
		"Starter 4-Way adapter must mate West (Habitat) and South (Solar) only")

	# 2-port linear chaining: power with reactor on North port, then lab(1,0) and mine(2,0) chain East.
	check(sim.place("reactor", Vector2i(0, -1)), "Place reactor on North port of 4-Way adapter")
	check(sim.place("lab", Vector2i(1, 0)), "Place lab east of 4-Way adapter")
	check(sim.buildings[Vector2i(1, 0)]["active"], "Chained lab must receive power and crew access")
	check(int(sim.buildings[Vector2i(0, 0)]["service_mask"])
		== (BuildingCatalog.BIT_N | BuildingCatalog.BIT_W | BuildingCatalog.BIT_S | BuildingCatalog.BIT_E),
		"4-Way adapter must dynamically update mask when all 4 cardinal modules connect")
	check(sim.place("mine", Vector2i(2, 0)), "Chain refinery onto 2-port lab")
	check(sim.buildings[Vector2i(2, 0)]["active"], "2-port chained refinery must connect through lab")

	# Flank-to-flank unmated Service sides must NOT share Service (water/O2/heat) without tunnel/adapter.
	var flank_sim := ColonySimulation.new()
	check(flank_sim.place("habitat", Vector2i(-1, 1), 1), "Place E-W habitat south of E-W starter habitat")
	check(not flank_sim.service_connected(Vector2i(-1, 0), Vector2i(-1, 1)),
		"Unmated flanks of 2-port modules must not form a service corridor")
	check(not flank_sim.buildings[Vector2i(-1, 1)]["active"],
		"Flank-only habitat must lack water/oxygen/heat service corridor")
	flank_sim.demolish(Vector2i(-1, 1))
	check(flank_sim.place("support_hub", Vector2i(1, 0)), "Place 4-Way adapter east of starter hub")
	check(flank_sim.place("habitat", Vector2i(1, 1)), "Auto-orient habitat south of new 4-Way adapter")
	check(flank_sim.buildings[Vector2i(1, 1)]["active"],
		"Habitat branching off 4-Way adapter must auto-orient and receive full service")

	# Dedicated Power Line: carries Power ONLY to remote crater reactor without sharing Service/Crew.
	var psim := ColonySimulation.new()
	psim.day = 21
	psim.recalculate()
	check(psim.safe_crew == 0, "Night must drop solar power")
	check(psim.place("reactor", Vector2i(4, 0), 3), "Place remote reactor separated by 3 empty tiles")
	check(psim.safe_crew == 0, "Unwired remote reactor must not power starter outpost")
	var path := psim.compute_line_path("power_line", Vector2i(1, 0), Vector2i(3, 0))
	check(path.size() == 3, "L-path across 3 tiles must have length 3")
	var placed_count := psim.place_line_path("power_line", path)
	check(placed_count == 3, "Drag-path placement must lay all 3 power line tiles")
	check(psim.safe_crew == 8, "Power line must carry reactor electricity back to starter outpost")
	check(psim.buildings[Vector2i(4, 0)]["service_network"] != psim.buildings[Vector2i(-1, 0)]["service_network"],
		"Power line must NOT merge service networks")
	# Remote lab powered via power line only (no service corridor to safe crew) stays offline for crew access.
	check(psim.place("lab", Vector2i(4, 1), 2), "Place lab next to remote reactor")
	check(psim.buildings[Vector2i(4, 1)]["powered"], "Remote lab must be powered by reactor")
	check(not psim.buildings[Vector2i(4, 1)]["active"], "Remote lab without service corridor to crew must not operate")
	var remote_snet: Dictionary = psim.service_networks[psim.buildings[Vector2i(4, 1)]["service_network"]]
	check("Crew access" in remote_snet["shortages"], "Inspector must diagnose missing Crew access")

	# Power line crossing over a Connection Tunnel coexists cleanly and demolishes top-down.
	var cross_cell := Vector2i(2, 2)
	check(psim.place("tunnel", cross_cell), "Place connection tunnel")
	check(psim.place("power_line", cross_cell), "Power line must cross cleanly over existing tunnel")
	check(psim.buildings.has(cross_cell) and psim.power_lines.has(cross_cell),
		"Tunnel and overhead power line must coexist on crossing cell")
	check(psim.demolish(cross_cell), "First demolish must remove overhead power line")
	check(psim.buildings.has(cross_cell) and not psim.power_lines.has(cross_cell),
		"Tunnel must remain intact after removing crossing power line")
	check(psim.demolish(cross_cell), "Second demolish must remove tunnel")
	check(not psim.buildings.has(cross_cell), "Tunnel must be removed on second demolish")

	# Atomic unaffordable drag path must not charge or mutate state.
	psim.credits = 10.0
	var lines_before := psim.power_lines.size()
	check(psim.place_line_path("power_line", [Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]) == 0,
		"Unaffordable drag path must fail atomically")
	check(psim.credits == 10.0 and psim.power_lines.size() == lines_before,
		"Failed drag path must not charge credits or lay partial lines")

	# Isolated auto-oriented module snaps when a 4-Way adapter is placed next to it.
	var snap_sim := ColonySimulation.new()
	check(snap_sim.place("ice", Vector2i(-4, 2)), "Place isolated ice extractor (default South)")
	check(int(snap_sim.buildings[Vector2i(-4, 2)]["facing"]) == 0, "Isolated module defaults to South (+Z)")
	check(snap_sim.place("support_hub", Vector2i(-3, 2)), "Place 4-Way adapter east of isolated module")
	check(int(snap_sim.buildings[Vector2i(-4, 2)]["facing"]) == 1,
		"Isolated auto-oriented module must turn East to dock with newly placed 4-Way adapter")
	check(snap_sim.service_connected(Vector2i(-4, 2), Vector2i(-3, 2)),
		"Snapped module must be service-connected to new 4-Way adapter")

	# Manual rotation locks orientation against auto-snapping.
	check(snap_sim.place("ice", Vector2i(-5, -2), 2), "Place manually rotated North ice extractor")
	check(not bool(snap_sim.buildings[Vector2i(-5, -2)]["auto_orient"]), "Manual placement must lock auto_orient off")
	check(snap_sim.place("support_hub", Vector2i(-4, -2)), "Place hub east of manually rotated module")
	check(int(snap_sim.buildings[Vector2i(-5, -2)]["facing"]) == 2,
		"Manually rotated module must keep its chosen orientation")


func test_night_cascade() -> void:
	var sim := ColonySimulation.new()
	sim.day = 20
	sim.recalculate()
	check(not sim.is_night() and sim.safe_crew == 8, "Day 20 should be lit")
	var morale := sim.morale
	sim.tick()
	check(sim.day == 21 and sim.is_night(), "Night begins on day 21")
	check(sim.safe_crew == 0 and sim.morale == morale - 3, "Night shortage must affect habitat and morale")
	for utility in ["power", "water", "oxygen", "heat"]:
		check(sim.totals(utility).x == 0, "Power loss must cascade to " + utility)
	check(sim.place("reactor", Vector2i(0, -1)), "Build reliable generation on north hub port")
	check(sim.safe_crew == 8, "Reactor must restore nighttime life support")
	sim.day = 30
	sim.tick()
	check(sim.day == 31 and not sim.is_night(), "Sunlight resumes on day 31")
	check(sim.safe_crew == 8, "Services must remain supplied after transition")


func productive_colony() -> ColonySimulation:
	var sim := ColonySimulation.new()
	check(sim.place("reactor", Vector2i(0, -1)), "Place charter reactor on hub North port")
	check(sim.place("lab", Vector2i(1, 0)), "Place charter lab on hub East port")
	check(sim.place("mine", Vector2i(2, 0)), "Chain charter refinery onto lab East port")
	return sim


func test_economy_and_charter() -> void:
	var sim := productive_colony()
	check(sim.credits == 620, "Starting build budget should leave 620 credits")
	sim.tick()
	check(sim.science == 1 and sim.exports == 2, "Production must accrue once per day")
	check(sim.credits == 624, "24 export income minus 20 upkeep must net 4")
	for i in range(28):
		sim.tick()
	check(sim.day == 30 and sim.science == 29, "Advance to exact pre-charter boundary")
	check(not sim.charter_complete, "Charter must not complete below science threshold")
	sim.tick()
	check(sim.charter_complete, "An affordable charter solution must complete")
	check(sim.credits == 1100, "Funding at day 31 must include science grant exactly once")
	check(sim.safe_crew == 8 and sim.morale == 100, "Charter solution must survive night")
	var threshold := ColonySimulation.new()
	threshold.day = 29
	threshold.science = 30
	threshold.exports = 40
	threshold.morale = 64.4
	threshold.tick()
	check(not threshold.charter_complete, "Morale below 65 must block charter")
	threshold.morale = 64.5
	threshold.tick()
	check(threshold.charter_complete, "Exact morale threshold must permit charter")
	sim.reset()
	check(sim.day == 1 and sim.science == 0 and sim.exports == 0 and sim.supplies == 0.0,
		"Restart must clear progress and supplies")
	check(not sim.charter_complete and sim.buildings.size() == 6,
		"Restart must restore starter colony including 4-Way adapter and landing pad")


func test_no_crew_production() -> void:
	var sim := productive_colony()
	sim.demolish(Vector2i(-1, 0))
	sim.tick()
	check(sim.crew == 0 and sim.science == 0 and sim.exports == 0, "No crew must mean no production")
	var unsafe := productive_colony()
	unsafe.place("habitat", Vector2i(7, 7))
	unsafe.tick()
	check(unsafe.science == 0 and unsafe.exports == 0, "Unsafe crew must halt production")


func test_determinism() -> void:
	var a := productive_colony()
	var b := productive_colony()
	for i in range(90):
		a.tick()
		b.tick()
	check(a.buildings == b.buildings and a.networks == b.networks and a.power_networks == b.power_networks,
		"Repeated commands must produce identical networks")
	check(a.credits == b.credits and a.science == b.science and a.morale == b.morale,
		"Repeated ticks must produce identical economy and morale")
	check(a.supplies == b.supplies and a.deliveries == b.deliveries,
		"Repeated ticks must produce identical supply deliveries")


func test_grading_and_landmarks() -> void:
	var sim := ColonySimulation.new()
	for cell in [
		Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(0, 1),
		ColonySimulation.STARTER_LANDING_PAD_CELL
	]:
		check(sim.graded.has(cell), "Starter outpost and landing pad must sit on graded pads")
		check(not sim.blocked.has(cell), "Starter outpost and landing pad must not be blocked")
	check(not sim.blocked.is_empty(), "Survey must contain immovable landmarks")
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(7, 7), Vector2i(-4, 0)]:
		check(not sim.blocked.has(cell), "Landmarks must not cover core starter/test cells")
	var blocked: Vector2i = sim.blocked.keys()[0]
	var credits := sim.credits
	check(not sim.place("tunnel", blocked), "Construction must be rejected on immovable features")
	check(not sim.place("power_line", blocked), "Power line must be rejected on immovable features")
	check(not sim.bulldoze(blocked) and sim.credits == credits, "Bulldozing immovable features must fail for free")
	check(sim.bulldoze(Vector2i(5, 5)), "Rough regolith must be bulldozable")
	check(sim.credits == credits - ColonySimulation.BULLDOZE_COST, "Bulldozing must charge its fee")
	check(not sim.bulldoze(Vector2i(5, 5)) and sim.credits == credits - ColonySimulation.BULLDOZE_COST,
		"Re-grading a pad must fail without charging")
	check(sim.place("tunnel", Vector2i(6, 5)) and sim.graded.has(Vector2i(6, 5)),
		"Construction must grade its own pad")
	check(not sim.bulldoze(Vector2i(11, 0)), "Bulldozing outside the site must fail")
	sim.demolish(Vector2i(6, 5))
	check(sim.graded.has(Vector2i(6, 5)), "Demolition must leave the graded scar")
	sim.reset()
	check(not sim.graded.has(Vector2i(5, 5)) and sim.graded.size() == 6,
		"Reset must restore untouched regolith and starter pads")


func test_landing_pad_deliveries() -> void:
	var sim := ColonySimulation.new()
	var pad_cell := ColonySimulation.STARTER_LANDING_PAD_CELL
	check(sim.buildings.has(pad_cell) and sim.buildings[pad_cell]["kind"] == "landing_pad",
		"New game must start with a default landing pad")
	check(sim.buildings[pad_cell]["active"], "Starter landing pad must be operational")
	var starter_delivery := sim.delivery_for_cell(pad_cell)
	check(not starter_delivery.is_empty() and starter_delivery["phase"] == "approaching",
		"Starter landing pad must begin with a visible approaching supply ship")
	check(sim.supplies == 0.0 and not starter_delivery["cargo_credited"],
		"Supply credit must not be applied before landing completes")
	var expected_first := ColonySimulation.DELIVERY_CREDIT_TIME - ColonySimulation.STARTER_INITIAL_CYCLE_TIME
	check(is_equal_approx(sim.time_to_next_delivery(int(starter_delivery["building_id"])), expected_first),
		"Starter landing pad must have a predictable first-delivery schedule")

	sim.advance(expected_first - 0.1)
	check(sim.delivery_for_cell(pad_cell)["phase"] == "delivering",
		"Ship must reach delivering phase before cargo is credited")
	check(sim.supplies == 0.0, "No supply may be credited before delivery finishes")

	sim.advance(0.15)
	check(is_equal_approx(sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Completed landing must credit one supply shipment")
	check(sim.deliveries_completed == 1 and sim.delivery_for_cell(pad_cell)["phase"] == "departing",
		"Lander must enter departing phase after crediting cargo")
	sim.advance(0.2)
	check(is_equal_approx(sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Departure frames must never double-credit supplies")

	sim.advance(ColonySimulation.SUPPLY_DELIVERY_INTERVAL * 2.0)
	check(is_equal_approx(sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT * 3.0),
		"Repeated deliveries must occur at the fixed interval")

	var one_pad := ColonySimulation.new()
	var two_pads := ColonySimulation.new()
	check(two_pads.place("landing_pad", Vector2i(3, -2)), "Player must be able to build additional landing pads")
	var span := ColonySimulation.SUPPLY_DELIVERY_INTERVAL * 3.0
	one_pad.advance(span)
	two_pads.advance(span)
	check(is_equal_approx(two_pads.supplies, one_pad.supplies * 2.0),
		"Two operational pads must yield twice the supplies of one over equivalent intervals")

	var abort_sim := ColonySimulation.new()
	abort_sim.advance(expected_first - 0.2)
	check(abort_sim.supplies == 0.0, "Supply must still be zero before offload finishes")
	check(abort_sim.demolish(pad_cell), "Demolishing pad during descent must succeed")
	check(abort_sim.deliveries.is_empty(), "Demolishing pad must remove its delivery schedule")
	abort_sim.advance(10.0)
	check(abort_sim.supplies == 0.0, "Removed pad must not leave stranded deliveries")

	var post_sim := ColonySimulation.new()
	post_sim.advance(expected_first + 0.05)
	check(is_equal_approx(post_sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Credited supply must exist during departure")
	post_sim.demolish(pad_cell)
	post_sim.advance(12.0)
	check(is_equal_approx(post_sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Demolishing pad during departure must preserve credited cargo without further deliveries")

	two_pads.reset()
	check(two_pads.supplies == 0.0 and two_pads.deliveries.size() == 1,
		"Restart must reset supplies and restore single starter delivery")
	check(two_pads.delivery_for_cell(pad_cell)["phase"] == "approaching",
		"Restart must restore starter approaching supply ship")


func test_structure_states_and_serialization() -> void:
	var sim := ColonySimulation.new()
	var solar_cell := Vector2i(0, 1)
	var pad_cell := ColonySimulation.STARTER_LANDING_PAD_CELL

	check(sim.set_building_build_progress(solar_cell, 0.5), "Should set partial build progress")
	check(not sim.buildings[solar_cell]["active"] and sim.safe_crew == 0,
		"Under-construction generator must not supply power")
	check(sim.set_building_build_progress(solar_cell, 1.0), "Completing construction must succeed")
	check(sim.buildings[solar_cell]["active"] and sim.safe_crew == 8,
		"Completed generator must restore colony power")

	check(sim.set_building_condition(solar_cell, ColonySimulation.CONDITION_DAMAGED),
		"Should mark structure damaged")
	check(not sim.buildings[solar_cell]["active"] and sim.safe_crew == 0,
		"Damaged generator must go offline")
	check(sim.set_building_condition(solar_cell, ColonySimulation.CONDITION_REPAIRING, 0.6),
		"Should mark structure repairing")
	check(not sim.buildings[solar_cell]["active"], "Repairing structure must stay offline until restored")
	check(sim.set_building_condition(solar_cell, ColonySimulation.CONDITION_OPERATIONAL),
		"Repaired structure must return to operational")
	check(sim.buildings[solar_cell]["active"] and sim.safe_crew == 8,
		"Restored structure must resume service")

	sim.set_building_condition(pad_cell, ColonySimulation.CONDITION_DAMAGED)
	check(sim.delivery_for_cell(pad_cell)["phase"] == "waiting",
		"Damaged landing pad must abort unlanded approach")
	sim.advance(8.0)
	check(sim.supplies == 0.0, "Damaged landing pad must not credit deliveries")

	# Save/load round-trip preserves structure states, facings, power_lines, and mid-visit deliveries.
	var save_src := ColonySimulation.new()
	save_src.place("lab", Vector2i(1, 0), 3)
	save_src.place("power_line", Vector2i(2, 0))
	save_src.set_building_build_progress(Vector2i(-3, 0), 0.5)
	save_src.set_building_condition(Vector2i(-2, 0), ColonySimulation.CONDITION_DAMAGED)
	save_src.set_building_condition(Vector2i(-1, 0), ColonySimulation.CONDITION_REPAIRING, 0.4)
	var first_t := ColonySimulation.DELIVERY_CREDIT_TIME - ColonySimulation.STARTER_INITIAL_CYCLE_TIME
	save_src.advance(first_t - 0.5)
	var snap_before := save_src.export_state()
	var restored_before := ColonySimulation.new()
	check(restored_before.import_state(snap_before), "Import state must succeed")
	check(int(restored_before.buildings[Vector2i(1, 0)]["facing"]) == 3
		and not bool(restored_before.buildings[Vector2i(1, 0)]["auto_orient"]),
		"Save/load must preserve manual facing and auto_orient flag")
	check(restored_before.power_lines.has(Vector2i(2, 0)),
		"Save/load must preserve power_lines")
	check(is_equal_approx(restored_before.buildings[Vector2i(-3, 0)]["build_progress"], 0.5),
		"Save/load must restore build_progress")
	check(restored_before.buildings[Vector2i(-2, 0)]["condition"] == ColonySimulation.CONDITION_DAMAGED,
		"Save/load must restore damaged condition")
	check(restored_before.buildings[Vector2i(-1, 0)]["condition"] == ColonySimulation.CONDITION_REPAIRING
		and is_equal_approx(restored_before.buildings[Vector2i(-1, 0)]["repair_progress"], 0.4),
		"Save/load must restore repairing condition and progress")
	restored_before.advance(0.6)
	check(is_equal_approx(restored_before.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Restored in-flight descent must credit cargo once on completion")

	var snap_after := restored_before.export_state()
	var restored_after := ColonySimulation.new()
	check(restored_after.import_state(snap_after), "Import mid-departure state must succeed")
	restored_after.advance(1.0)
	check(is_equal_approx(restored_after.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Restored departing visit must not duplicate already-credited cargo")
	restored_after.advance(ColonySimulation.SUPPLY_DELIVERY_INTERVAL)
	check(is_equal_approx(restored_after.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT * 2.0),
		"Restored departing visit must resume recurring deliveries on schedule")

	# Legacy v1 save compatibility ("link" migrates cleanly to "tunnel").
	var legacy_v1 := {
		"version": 1,
		"day": 5,
		"credits": 900.0,
		"buildings": [
			{"cell": [0, 0], "id": 1, "kind": "link"}
		],
		"graded": [[0, 0]],
	}
	var migrated := ColonySimulation.new()
	check(migrated.import_state(legacy_v1), "Legacy v1 save must import cleanly")
	check(migrated.buildings[Vector2i(0, 0)]["kind"] == "tunnel",
		"Legacy 'link' must migrate to 'tunnel'")
