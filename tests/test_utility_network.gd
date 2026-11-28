extends SceneTree

var failures := 0


func _init() -> void:
	test_distinct_layers_and_ports()
	test_priority_load_shedding()
	test_storage_conservation_and_reserve_policy()
	test_transport_capacity_and_losses()
	test_recycling_conservation()
	test_deterministic_order_and_cycle_convergence()
	test_upstream_cause_diagnostics_and_isolation()
	test_simulation_integration_and_serialization()
	if failures == 0:
		print("PASS: utility layers, priorities, storage conservation, capacity/loss, cycles, diagnostics and isolation")
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _make_building(id: int, kind: String, extra: Dictionary = {}) -> Dictionary:
	var b := {
		"id": id,
		"kind": kind,
		"active": false,
		"network": -1,
		"build_progress": 1.0,
		"condition": ColonySimulation.CONDITION_OPERATIONAL,
		"repair_progress": 1.0,
		"isolated": false,
		"status_reason": "Operational",
		"stored": {},
	}
	for k in extra:
		b[k] = extra[k]
	return b


func _extended_catalog() -> Dictionary:
	var cat := BuildingCatalog.DATA.duplicate(true)
	cat["battery"] = {
		"name": "Battery bank",
		"cost": 180,
		"upkeep": 1,
		"power_storage": 30.0,
		"power_charge_rate": 10.0,
		"power_discharge_rate": 12.0,
	}
	cat["water_tank"] = {
		"name": "Water tank",
		"cost": 140,
		"upkeep": 1,
		"water_storage": 20.0,
		"water_charge_rate": 8.0,
		"water_discharge_rate": 8.0,
	}
	cat["power_cable"] = {
		"name": "Power cable",
		"cost": 10,
		"upkeep": 0,
		"layers": ["power"],
	}
	cat["bottleneck_link"] = {
		"name": "Narrow bus",
		"cost": 10,
		"upkeep": 0,
		"power_capacity": 6.0,
	}
	cat["leaky_link"] = {
		"name": "Leaky conduit",
		"cost": 10,
		"upkeep": 0,
		"power_loss": 0.25,
	}
	cat["recycling_hab"] = {
		"name": "Closed-loop habitat",
		"cost": 300,
		"upkeep": 2,
		"power_use": 3.0,
		"water_use": 4.0,
		"water_recycle": 0.5,
		"oxygen_use": 2.0,
		"heat_use": 2.0,
	}
	cat["cycle_a"] = {
		"name": "Cycle node A",
		"cost": 100,
		"upkeep": 0,
		"power_use": 2.0,
		"water": 4.0,
	}
	cat["cycle_b"] = {
		"name": "Cycle node B",
		"cost": 100,
		"upkeep": 0,
		"water_use": 2.0,
		"power": 4.0,
	}
	return cat


func test_distinct_layers_and_ports() -> void:
	var cat := _extended_catalog()
	# Power-only cable connects solar + ice on power, but does NOT carry water to oxygen/habitat.
	var buildings := {
		Vector2i(0, 0): _make_building(1, "solar"),
		Vector2i(1, 0): _make_building(2, "ice"),
		Vector2i(2, 0): _make_building(3, "power_cable"),
		Vector2i(3, 0): _make_building(4, "oxygen"),
		Vector2i(4, 0): _make_building(5, "habitat"),
	}
	var eval := UtilityNetwork.evaluate(buildings, false, cat)
	check(eval["active"][Vector2i(1, 0)], "Ice extractor must receive power")
	check(not eval["active"][Vector2i(3, 0)], "Power-only cable must not carry water to life support")
	check(not eval["active"][Vector2i(4, 0)], "Habitat must stay offline without connected water/oxygen")
	check(eval["layer_graph"]["power"]["components"].size() == 1,
		"All 5 nodes must share one power component")
	check(eval["layer_graph"]["water"]["components"].size() == 2,
		"Power-only cable must split water into 2 disconnected components")

	# Directional port test: solar only exposes power port to RIGHT (+1, 0), not LEFT (-1, 0).
	var directional := {
		Vector2i(0, 0): _make_building(1, "solar", {"ports": {"power": [Vector2i.RIGHT]}}),
		Vector2i(-1, 0): _make_building(2, "lab"),
		Vector2i(1, 0): _make_building(3, "lab"),
	}
	var dir_eval := UtilityNetwork.evaluate(directional, false, cat)
	check(dir_eval["active"][Vector2i(1, 0)], "Connected port side must receive power")
	check(not dir_eval["active"][Vector2i(-1, 0)], "Unported side must not receive power")


func test_priority_load_shedding() -> void:
	var sim := ColonySimulation.new()
	# Starter outpost: solar = 12 power; ice(3) + oxygen(3) + habitat(3) = 9 power.
	# Add lab(4) -> total demand = 13 > 12. Priority shedding must protect ice/oxygen/habitat and shed lab!
	check(sim.place("lab", Vector2i(1, 0)), "Place lab adjacent to solar")
	check(sim.buildings[Vector2i(-3, 0)]["active"], "Life-support ice extractor must stay online")
	check(sim.buildings[Vector2i(-2, 0)]["active"], "Life-support oxygen module must stay online")
	check(sim.buildings[Vector2i(-1, 0)]["active"], "Habitat must be protected over production lab")
	check(sim.safe_crew == 8, "Crew must remain safe when low-priority lab is shed")
	check(not sim.buildings[Vector2i(1, 0)]["active"], "Low-priority lab must be shed first")
	check("Shed" in str(sim.buildings[Vector2i(1, 0)]["status_reason"]),
		"Shed production building must report priority-shed reason")
	var net: Dictionary = sim.networks[sim.buildings[Vector2i(1, 0)]["network"]]
	check(Vector2i(1, 0) in net["shed_cells"], "Network diagnostics must list shed cells")


func test_storage_conservation_and_reserve_policy() -> void:
	var cat := _extended_catalog()
	# Solar(12) + ice(3) + oxygen(3) + habitat(3) + battery(cap 30, charge 10, discharge 12) + lab(4).
	# In daylight: solar=12, demand=13 -> lab shed, surplus=3 -> battery charges by 3/day!
	var buildings := {
		Vector2i(-3, 0): _make_building(1, "ice"),
		Vector2i(-2, 0): _make_building(2, "oxygen"),
		Vector2i(-1, 0): _make_building(3, "habitat"),
		Vector2i(0, 0): _make_building(4, "solar"),
		Vector2i(0, 1): _make_building(5, "battery", {"stored": {"power": 0.0}}),
		Vector2i(1, 0): _make_building(6, "lab"),
	}
	# Step 1: Charge during daylight under protect_essential (floor 25% = 7.5).
	# Initial stored=0 -> cannot power lab, surplus=3 charges battery to 3.0.
	var ev1 := UtilityNetwork.evaluate(buildings, false, cat,
		UtilityNetwork.RESERVE_POLICY_PROTECT_ESSENTIAL, 0.25)
	check(ev1["active"][Vector2i(-1, 0)] and not ev1["active"][Vector2i(1, 0)],
		"Empty battery must protect habitat and shed lab")
	check(UtilityNetwork.apply_storage_step(buildings, ev1, 1.0, cat),
		"Surplus generation must charge battery")
	check(is_equal_approx(float(buildings[Vector2i(0, 1)]["stored"]["power"]), 3.0),
		"Battery must conserve exact surplus (12 - 9 = 3)")

	# Charge up to cap with lab isolated (net surplus = +3/day -> clamps strictly at 30.0).
	buildings[Vector2i(1, 0)]["isolated"] = true
	for i in range(15):
		var ev := UtilityNetwork.evaluate(buildings, false, cat,
			UtilityNetwork.RESERVE_POLICY_PROTECT_ESSENTIAL, 0.25)
		UtilityNetwork.apply_storage_step(buildings, ev, 1.0, cat)
	check(is_equal_approx(float(buildings[Vector2i(0, 1)]["stored"]["power"]), 30.0),
		"Battery charge must clamp at capacity (30.0)")
	buildings[Vector2i(1, 0)]["isolated"] = false

	# Nighttime discharge with protect_essential (floor 25% = 7.5):
	# Demand: ice(3) + oxygen(3) + habitat(3) = 9 essential, lab(4) = discretionary.
	# Discharge rate = 12/day, so night day 1 discharges 9 (lab needs 4 -> 9+4=13 > 12 rate, so lab shed).
	var night1 := UtilityNetwork.evaluate(buildings, true, cat,
		UtilityNetwork.RESERVE_POLICY_PROTECT_ESSENTIAL, 0.25)
	check(night1["active"][Vector2i(-1, 0)], "Charged battery must keep habitat alive at night")
	check(not night1["active"][Vector2i(1, 0)], "Discharge rate cap (12) must shed lab (total 13)")
	var net_n1: Dictionary = night1["networks"][0]
	check(is_equal_approx(float(net_n1["reserve_days"]["power"]), 30.0 / 9.0),
		"Reserve duration must equal stored / discharge_rate (30 / 9 days)")
	UtilityNetwork.apply_storage_step(buildings, night1, 1.0, cat)
	check(is_equal_approx(float(buildings[Vector2i(0, 1)]["stored"]["power"]), 21.0),
		"Night discharge must deduct exact consumed power (30 - 9 = 21)")

	# Test reserve floor protection: set stored = 7.0 (< 7.5 floor) and remove ice/oxygen/habitat, leaving only lab(4).
	var floor_buildings := {
		Vector2i(0, 0): _make_building(1, "battery", {"stored": {"power": 7.0}}),
		Vector2i(1, 0): _make_building(2, "lab"),
	}
	var protected := UtilityNetwork.evaluate(floor_buildings, true, cat,
		UtilityNetwork.RESERVE_POLICY_PROTECT_ESSENTIAL, 0.25)
	check(not protected["active"][Vector2i(1, 0)],
		"protect_essential policy must refuse discharging below reserve floor for production lab")
	var balanced := UtilityNetwork.evaluate(floor_buildings, true, cat,
		UtilityNetwork.RESERVE_POLICY_BALANCED, 0.25)
	check(balanced["active"][Vector2i(1, 0)],
		"balanced policy must permit discharging reserve for production lab")


func test_transport_capacity_and_losses() -> void:
	var cat := _extended_catalog()
	# Bottleneck link caps power at 6.0 even though solar produces 12.0.
	# Two labs (4 power each = 8 demand): only 1 lab fits under 6.0 cap!
	var capped := {
		Vector2i(0, 0): _make_building(1, "solar"),
		Vector2i(1, 0): _make_building(2, "bottleneck_link"),
		Vector2i(2, 0): _make_building(3, "lab"),
		Vector2i(3, 0): _make_building(4, "lab"),
	}
	var ev_cap := UtilityNetwork.evaluate(capped, false, cat)
	check(ev_cap["active"][Vector2i(2, 0)] and not ev_cap["active"][Vector2i(3, 0)],
		"Transport capacity bottleneck (6) must allow 1 lab (4) and shed the second")

	# Leaky link has 25% power loss: solar(12) -> 9.0 effective power.
	# Two mines (5 power each = 10 demand): only 1 mine fits in 9.0 effective supply.
	var leaky := {
		Vector2i(0, 0): _make_building(1, "solar"),
		Vector2i(1, 0): _make_building(2, "leaky_link"),
		Vector2i(2, 0): _make_building(3, "mine"),
		Vector2i(3, 0): _make_building(4, "mine"),
	}
	var ev_leak := UtilityNetwork.evaluate(leaky, false, cat)
	check(is_equal_approx(float(ev_leak["networks"][0]["supply"]["power"]), 9.0),
		"25%% transport loss must reduce 12 power to 9 effective power")
	check(ev_leak["active"][Vector2i(2, 0)] and not ev_leak["active"][Vector2i(3, 0)],
		"Transport loss must shed demand exceeding effective supply")


func test_recycling_conservation() -> void:
	var cat := _extended_catalog()
	# Two recycling habitats use 8 water total, recycle 50% (4 water) when active.
	# Without any water source, recycling alone must NEVER bootstrap or create water!
	var no_source := {
		Vector2i(0, 0): _make_building(1, "reactor"),
		Vector2i(1, 0): _make_building(2, "recycling_hab"),
	}
	var ev_none := UtilityNetwork.evaluate(no_source, false, cat)
	check(not ev_none["active"][Vector2i(1, 0)],
		"Recycling must not create water without an external water source")
	check(is_equal_approx(float(ev_none["networks"][0]["supply"]["water"]), 0.0),
		"Inactive recycler must produce zero water")


func test_deterministic_order_and_cycle_convergence() -> void:
	var cat := _extended_catalog()
	# Pure circular dependency (cycle_a needs power -> makes water; cycle_b needs water -> makes power)
	# with no external generator must converge conservatively to both offline!
	var dead_cycle := {
		Vector2i(0, 0): _make_building(1, "cycle_a"),
		Vector2i(1, 0): _make_building(2, "cycle_b"),
	}
	var ev_dead := UtilityNetwork.evaluate(dead_cycle, false, cat)
	check(ev_dead["converged"], "Circular dependency must converge within bounded iterations")
	check(not ev_dead["active"][Vector2i(0, 0)] and not ev_dead["active"][Vector2i(1, 0)],
		"Unpowered circular dependency must not self-bootstrap")

	# Dictionary insertion order invariance: build identical layout in opposite insertion orders.
	var order_a := {
		Vector2i(0, 0): _make_building(1, "solar"),
		Vector2i(1, 0): _make_building(2, "lab"),
		Vector2i(2, 0): _make_building(3, "lab"),
		Vector2i(3, 0): _make_building(4, "lab"),
		Vector2i(4, 0): _make_building(5, "lab"),
	}
	var order_b := {
		Vector2i(4, 0): _make_building(5, "lab"),
		Vector2i(3, 0): _make_building(4, "lab"),
		Vector2i(2, 0): _make_building(3, "lab"),
		Vector2i(1, 0): _make_building(2, "lab"),
		Vector2i(0, 0): _make_building(1, "solar"),
	}
	var ev_a := UtilityNetwork.evaluate(order_a, false, cat)
	var ev_b := UtilityNetwork.evaluate(order_b, false, cat)
	check(ev_a["active"] == ev_b["active"],
		"Evaluation must be invariant to dictionary insertion order")
	check(ev_a["networks"][0]["shed_cells"] == ev_b["networks"][0]["shed_cells"],
		"Shed cell selection must be deterministic regardless of insertion order")


func test_upstream_cause_diagnostics_and_isolation() -> void:
	var sim := ColonySimulation.new()
	# Trigger lunar night -> verify upstream cause chain identifies solar night -> ice -> life support.
	sim.day = 21
	sim.recalculate()
	var hab_net: Dictionary = sim.networks[sim.buildings[Vector2i(-1, 0)]["network"]]
	var joined_causes := " | ".join(hab_net["causes"])
	check("lunar night" in joined_causes,
		"Night diagnostics must identify solar arrays offline during lunar night")
	check("upstream Power shortage" in joined_causes,
		"Downstream water/oxygen shortages must trace to upstream Power shortage")

	# Daylight damaged solar -> verify cause identifies damaged generator.
	sim.day = 1
	sim.set_building_condition(Vector2i(0, 0), ColonySimulation.CONDITION_DAMAGED)
	hab_net = sim.networks[sim.buildings[Vector2i(-1, 0)]["network"]]
	check("damaged" in " | ".join(hab_net["causes"]).to_lower(),
		"Damaged generator must be identified as upstream root cause")
	sim.set_building_condition(Vector2i(0, 0), ColonySimulation.CONDITION_OPERATIONAL)
	check(sim.safe_crew == 8 and hab_net.has("causes"), "Restored generator restores crew safety")

	# Isolation action: isolate solar array -> disconnects it from network without demolishing.
	check(sim.set_building_isolated(Vector2i(0, 0), true), "Should isolate solar array")
	check(not sim.buildings[Vector2i(0, 0)]["active"] and sim.safe_crew == 0,
		"Isolated generator must not supply adjacent modules")
	check("Isolated" in str(sim.buildings[Vector2i(0, 0)]["status_reason"]),
		"Isolated module must report isolated status")
	check(sim.set_building_isolated(Vector2i(0, 0), false), "Should reconnect solar array")
	check(sim.safe_crew == 8, "Reconnecting generator must restore crew safety")


func test_simulation_integration_and_serialization() -> void:
	var sim := ColonySimulation.new()
	check(sim.set_reserve_policy(UtilityNetwork.RESERVE_POLICY_BALANCED, 0.4),
		"Should update reserve policy and floor")
	check(sim.set_building_isolated(Vector2i(0, 0), true), "Should isolate solar for save test")
	var snap := sim.export_state()
	var restored := ColonySimulation.new()
	check(restored.import_state(snap), "Import state must succeed")
	check(restored.reserve_policy == UtilityNetwork.RESERVE_POLICY_BALANCED,
		"Save/load must preserve reserve policy")
	check(is_equal_approx(restored.reserve_floor, 0.4),
		"Save/load must preserve reserve floor")
	check(bool(restored.buildings[Vector2i(0, 0)]["isolated"]),
		"Save/load must preserve building isolation flag")
	check(restored.safe_crew == 0, "Restored isolated solar must keep network offline")
