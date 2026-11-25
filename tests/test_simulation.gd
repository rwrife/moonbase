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
	if failures == 0:
		print("PASS: placement, topology, cascades, economy, charter, determinism and grading")
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
	check(sim.safe_crew == 8, "Starter outpost must be supplied")
	check(sim.place("habitat", Vector2i(2, 0)), "Place isolated habitat")
	check(sim.networks.size() == 2, "Separated cells must form distinct components")
	check(not sim.buildings[Vector2i(2, 0)]["active"], "Remote supply must not serve isolated habitat")
	check(sim.place("link", Vector2i(1, 0)), "Bridge isolated habitat")
	check(sim.networks.size() == 1 and sim.safe_crew == 16, "Link must merge networks and restore service")
	check(sim.demolish(Vector2i(1, 0)), "Remove bridge")
	check(sim.networks.size() == 2 and sim.safe_crew == 8, "Removing bridge must split networks")
	check(sim.place("solar", Vector2i(3, 1)), "Place diagonal generator")
	check(sim.networks.size() == 3, "Diagonal neighbors must not connect")
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
	check(sim.day == 1 and sim.science == 0 and sim.exports == 0, "Restart must clear progress")
	check(not sim.charter_complete and sim.buildings.size() == 4, "Restart must restore starter colony")


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


func test_grading_and_landmarks() -> void:
	var sim := ColonySimulation.new()
	for cell in [Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0)]:
		check(sim.graded.has(cell), "Starter outpost must sit on graded pads")
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
	check(not sim.graded.has(Vector2i(5, 5)) and sim.graded.size() == 4, "Reset must restore untouched regolith")
