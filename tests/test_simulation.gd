extends SceneTree

var failures := 0


func _init() -> void:
	test_placement()
	test_connections()
	test_night_cascade()
	test_economy_and_charter()
	test_no_crew_production()
	test_determinism()
	test_grading_and_landmarks()
	test_landing_pad_deliveries()
	test_structure_states_and_serialization()
	if failures == 0:
		print("PASS: placement, topology, cascades, economy, charter, determinism, grading, deliveries and states")
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
	check(not sim.place("link", Vector2i(1, 0)), "Unaffordable placement must fail")
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
	check(sim.place("habitat", Vector2i(2, 0)), "Place isolated habitat")
	check(sim.networks.size() == base_networks + 1, "Separated cells must form distinct components")
	check(not sim.buildings[Vector2i(2, 0)]["active"], "Remote supply must not serve isolated habitat")
	check(sim.place("link", Vector2i(1, 0)), "Bridge isolated habitat")
	check(sim.networks.size() == base_networks and sim.safe_crew == 16, "Link must merge networks and restore service")
	check(sim.demolish(Vector2i(1, 0)), "Remove bridge")
	check(sim.networks.size() == base_networks + 1 and sim.safe_crew == 8, "Removing bridge must split networks")
	check(sim.place("solar", Vector2i(3, 1)), "Place diagonal generator")
	check(sim.networks.size() == base_networks + 2, "Diagonal neighbors must not connect")
	var local: Dictionary = sim.networks[sim.buildings[Vector2i(2, 0)]["network"]]
	check(local["supply"]["power"] == 0, "Isolated component cannot borrow global surplus")
	check("Power" in local["shortages"], "Inspection must identify local shortage")


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
	check(sim.place("reactor", Vector2i(0, 1)), "Build reliable generation")
	check(sim.safe_crew == 8, "Reactor must restore nighttime life support")
	sim.day = 30
	sim.tick()
	check(sim.day == 31 and not sim.is_night(), "Sunlight resumes on day 31")
	check(sim.safe_crew == 8, "Services must remain supplied after transition")


func productive_colony() -> ColonySimulation:
	var sim := ColonySimulation.new()
	check(sim.place("reactor", Vector2i(0, 1)), "Place charter reactor")
	check(sim.place("lab", Vector2i(1, 1)), "Place charter lab")
	check(sim.place("mine", Vector2i(1, 0)), "Place charter refinery")
	return sim


func test_economy_and_charter() -> void:
	var sim := productive_colony()
	check(sim.credits == 620, "Starting build budget should leave 620 credits")
	sim.tick()
	check(sim.science == 1 and sim.exports == 2, "Production must accrue once per day")
	check(sim.credits == 625, "24 export income minus 19 upkeep must net 5")
	for i in range(28):
		sim.tick()
	check(sim.day == 30 and sim.science == 29, "Advance to exact pre-charter boundary")
	check(not sim.charter_complete, "Charter must not complete below science threshold")
	sim.tick()
	check(sim.charter_complete, "An affordable charter solution must complete")
	check(sim.credits == 1130, "Funding at day 31 must include science grant exactly once")
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
	check(not sim.charter_complete and sim.buildings.size() == 5,
		"Restart must restore starter colony including starter landing pad")


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
	check(a.buildings == b.buildings and a.networks == b.networks, "Repeated commands must produce identical networks")
	check(a.credits == b.credits and a.science == b.science and a.morale == b.morale,
		"Repeated ticks must produce identical economy and morale")
	check(a.supplies == b.supplies and a.deliveries == b.deliveries,
		"Repeated ticks must produce identical supply deliveries")


func test_grading_and_landmarks() -> void:
	var sim := ColonySimulation.new()
	for cell in [
		Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0),
		ColonySimulation.STARTER_LANDING_PAD_CELL
	]:
		check(sim.graded.has(cell), "Starter outpost and landing pad must sit on graded pads")
		check(not sim.blocked.has(cell), "Starter outpost and landing pad must not be blocked")
	check(not sim.blocked.is_empty(), "Survey must contain immovable landmarks")
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(7, 7), Vector2i(-4, 0)]:
		check(not sim.blocked.has(cell), "Landmarks must not cover core starter/test cells")
	var blocked: Vector2i = sim.blocked.keys()[0]
	var credits := sim.credits
	check(not sim.place("link", blocked), "Construction must be rejected on immovable features")
	check(not sim.bulldoze(blocked) and sim.credits == credits, "Bulldozing immovable features must fail for free")
	check(sim.bulldoze(Vector2i(5, 5)), "Rough regolith must be bulldozable")
	check(sim.credits == credits - ColonySimulation.BULLDOZE_COST, "Bulldozing must charge its fee")
	check(not sim.bulldoze(Vector2i(5, 5)) and sim.credits == credits - ColonySimulation.BULLDOZE_COST,
		"Re-grading a pad must fail without charging")
	check(sim.place("link", Vector2i(6, 5)) and sim.graded.has(Vector2i(6, 5)),
		"Construction must grade its own pad")
	check(not sim.bulldoze(Vector2i(11, 0)), "Bulldozing outside the site must fail")
	sim.demolish(Vector2i(6, 5))
	check(sim.graded.has(Vector2i(6, 5)), "Demolition must leave the graded scar")
	sim.reset()
	check(not sim.graded.has(Vector2i(5, 5)) and sim.graded.size() == 5,
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

	# Advance into descending and delivering, stopping just before credit completes.
	sim.advance(expected_first - 0.1)
	check(sim.delivery_for_cell(pad_cell)["phase"] == "delivering",
		"Ship must reach delivering phase before cargo is credited")
	check(sim.supplies == 0.0, "No supply may be credited before delivery finishes")

	# Finish delivery; credit must apply once, then remain unchanged through departure.
	sim.advance(0.15)
	check(is_equal_approx(sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Completed landing must credit one supply shipment")
	check(sim.deliveries_completed == 1 and sim.delivery_for_cell(pad_cell)["phase"] == "departing",
		"Lander must enter departing phase after crediting cargo")
	sim.advance(0.2)
	check(is_equal_approx(sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Departure frames must never double-credit supplies")

	# Fixed interval: advance exactly two full intervals (12 days) -> +2 deliveries.
	sim.advance(ColonySimulation.SUPPLY_DELIVERY_INTERVAL * 2.0)
	check(is_equal_approx(sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT * 3.0),
		"Repeated deliveries must occur at the fixed interval")

	# Two operational pads yield twice the supplies of one over equivalent intervals.
	var one_pad := ColonySimulation.new()
	var two_pads := ColonySimulation.new()
	check(two_pads.place("landing_pad", Vector2i(3, -2)), "Player must be able to build additional landing pads")
	var span := ColonySimulation.SUPPLY_DELIVERY_INTERVAL * 3.0
	one_pad.advance(span)
	two_pads.advance(span)
	check(is_equal_approx(two_pads.supplies, one_pad.supplies * 2.0),
		"Two operational pads must yield twice the supplies of one over equivalent intervals")

	# Demolishing a pad before delivery completes cancels delivery with zero credit.
	var abort_sim := ColonySimulation.new()
	abort_sim.advance(expected_first - 0.2)
	check(abort_sim.supplies == 0.0, "Supply must still be zero before offload finishes")
	check(abort_sim.demolish(pad_cell), "Demolishing pad during descent must succeed")
	check(abort_sim.deliveries.is_empty(), "Demolishing pad must remove its delivery schedule")
	abort_sim.advance(10.0)
	check(abort_sim.supplies == 0.0, "Removed pad must not leave stranded deliveries")

	# Demolishing a pad after credit during departure preserves credited supplies without duplication.
	var post_sim := ColonySimulation.new()
	post_sim.advance(expected_first + 0.05)
	check(is_equal_approx(post_sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Credited supply must exist during departure")
	post_sim.demolish(pad_cell)
	post_sim.advance(12.0)
	check(is_equal_approx(post_sim.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Demolishing pad during departure must preserve credited cargo without further deliveries")

	# Restart restores starter pad and initial schedule.
	two_pads.reset()
	check(two_pads.supplies == 0.0 and two_pads.deliveries.size() == 1,
		"Restart must reset supplies and restore single starter delivery")
	check(two_pads.delivery_for_cell(pad_cell)["phase"] == "approaching",
		"Restart must restore starter approaching supply ship")


func test_structure_states_and_serialization() -> void:
	var sim := ColonySimulation.new()
	var solar_cell := Vector2i(0, 0)
	var pad_cell := ColonySimulation.STARTER_LANDING_PAD_CELL

	# Under construction takes structure offline and removes its utility output.
	check(sim.set_building_build_progress(solar_cell, 0.5), "Should set partial build progress")
	check(not sim.buildings[solar_cell]["active"] and sim.safe_crew == 0,
		"Under-construction generator must not supply power")
	check(sim.set_building_build_progress(solar_cell, 1.0), "Completing construction must succeed")
	check(sim.buildings[solar_cell]["active"] and sim.safe_crew == 8,
		"Completed generator must restore colony power")

	# Damaged and repairing states take structure offline; operational restores it.
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

	# Damaged landing pad aborts unlanded approach without crediting supplies.
	sim.set_building_condition(pad_cell, ColonySimulation.CONDITION_DAMAGED)
	check(sim.delivery_for_cell(pad_cell)["phase"] == "waiting",
		"Damaged landing pad must abort unlanded approach")
	sim.advance(8.0)
	check(sim.supplies == 0.0, "Damaged landing pad must not credit deliveries")

	# Save/load round-trip preserves structure states and mid-visit delivery state without duplication.
	var save_src := ColonySimulation.new()
	save_src.set_building_build_progress(Vector2i(-3, 0), 0.5)
	save_src.set_building_condition(Vector2i(-2, 0), ColonySimulation.CONDITION_DAMAGED)
	save_src.set_building_condition(Vector2i(-1, 0), ColonySimulation.CONDITION_REPAIRING, 0.4)
	var first_t := ColonySimulation.DELIVERY_CREDIT_TIME - ColonySimulation.STARTER_INITIAL_CYCLE_TIME
	# Snapshot mid-descent (before credit).
	save_src.advance(first_t - 0.5)
	var snap_before := save_src.export_state()
	var restored_before := ColonySimulation.new()
	check(restored_before.import_state(snap_before), "Import state must succeed")
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

	# Snapshot mid-departure (after credit) must not double-credit on resume.
	var snap_after := restored_before.export_state()
	var restored_after := ColonySimulation.new()
	check(restored_after.import_state(snap_after), "Import mid-departure state must succeed")
	restored_after.advance(1.0)
	check(is_equal_approx(restored_after.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Restored departing visit must not duplicate already-credited cargo")
	restored_after.advance(ColonySimulation.SUPPLY_DELIVERY_INTERVAL)
	check(is_equal_approx(restored_after.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT * 2.0),
		"Restored departing visit must resume recurring deliveries on schedule")
