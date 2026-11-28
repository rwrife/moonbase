extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game: ColonyGame = packed.instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.site.models.size() == 5, "Scene must display starter modules including landing pad")
	check_module_visuals(game)
	check_day_night_fade(game)
	check_structure_states(game)
	await check_landing_pad_and_supply_ships(game)
	check(game.camera_rig.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"Gameplay camera must be orthographic")
	for entry in [
		["pan_left", KEY_LEFT], ["pan_right", KEY_RIGHT],
		["pan_up", KEY_UP], ["pan_down", KEY_DOWN]
	]:
		var events := InputMap.action_get_events(entry[0])
		check(events[1].physical_keycode == entry[1], "Arrow key mapping must match " + entry[0])
	var button: Button = game.hud.tool_buttons["reactor"]
	await click(button.get_global_rect().get_center())
	check(game.tool == "reactor", "HUD must select construction mode")
	check(game.simulation.buildings.size() == 5, "UI clicks must not place world modules")
	var build_screen := game.camera_rig.camera.unproject_position(
		game.site.surface_position(Vector2i(0, 1)))
	await click(build_screen)
	check(game.site.models.size() == 6, "Construction must synchronize world visuals")
	var credits: float = game.simulation.credits
	await click(build_screen)
	check(game.simulation.credits == credits and game.site.models.size() == 6,
		"Clicking an occupied cell must not charge or add a duplicate visual")
	check(game.hud.event_log.text == "This tile is occupied.", "World rejection must reach HUD")
	game.select_tool("")
	game.activate_cell(Vector2i(0, 1))
	check("Fission reactor" in game.hud.inspector.text, "Selection must inspect local module")
	game.select_tool("demolish")
	game.activate_cell(Vector2i(0, 1))
	await process_frame
	check(game.site.models.size() == 5, "Demolition must remove visual module")
	var pad := Vector2i(4, -4)
	var rough := game.site.terrain.pad_targets.has(pad)
	var hidden_before := _visible_rocks(game.site, pad)
	game.select_tool("bulldoze")
	check(game.hud.tool_buttons["bulldoze"].button_pressed, "HUD must show bulldoze mode")
	game.activate_cell(pad)
	check(not rough and game.site.terrain.pad_targets.has(pad), "Bulldozing must grade the terrain")
	var level: float = game.site.terrain.pad_targets[pad]
	var center := LunarSite.cell_position(pad)
	var flat := true
	for offset in [Vector2(-0.9, -0.9), Vector2(0.9, 0.9), Vector2(0.9, -0.9), Vector2(0, 0)]:
		flat = flat and absf(game.site.terrain.height_at(center.x + offset.x, center.z + offset.y) - level) < 0.002
	check(flat, "Graded pad must be level")
	check(_visible_rocks(game.site, pad) == 0, "Bulldozing must clear rocks (had %d)" % hidden_before)
	var blocked: Vector2i = game.simulation.blocked.keys()[0]
	check(not game.tool_error(blocked).is_empty(), "Preview must reject immovable landmarks")
	game.select_tool("")
	game.activate_cell(blocked)
	check("Immovable" in game.hud.inspector.text, "Inspector must describe immovable terrain")
	game.toggle_pause()
	for i in range(8):
		game.advance(0.25)
	check(game.simulation.day == 1, "Pause must freeze simulation")
	game.toggle_pause()
	game.hud.speed_buttons[1].pressed.emit()
	check(game.speed == 1, "HUD must select 1x speed")
	for i in range(4):
		game.advance(0.25)
	check(game.simulation.day == 1, "1x clock must move slower than one day per second")
	for i in range(12):
		game.advance(0.25)
	check(game.simulation.day == 2, "1x must tick once every SECONDS_PER_DAY seconds")
	game.hud.speed_buttons[4].pressed.emit()
	check(game.speed == 4, "HUD must select 4x speed")
	for i in range(4):
		game.advance(0.25)
	check(game.simulation.day == 3, "4x must tick four times faster than 1x")
	game.advance(60)
	check(game.simulation.day == 3, "Background gaps must not fast-forward the colony")
	game.restart()
	check(not game.site.terrain.pad_targets.has(pad) and _visible_rocks(game.site, pad) == hidden_before,
		"Restart must restore undisturbed regolith and rocks")
	check(game.simulation.day == 1 and game.speed == 1 and not game.paused,
		"Restart must clear clock, pause, speed and scenario")
	game.simulation.demolish(Vector2i(0, 0))
	game.simulation.place("reactor", Vector2i(0, 0))
	game.restart()
	check(game.site.models[Vector2i(0, 0)].get_meta("kind") == "solar",
		"Restart must replace visuals when a starter module changed type")
	check(game.site.models[Vector2i(0, 0)].operating_time == 0.0,
		"Replacement starter modules must begin with a fresh animation clock")
	var cell := Vector2i(-3, 2)
	var screen: Vector2 = game.camera_rig.camera.unproject_position(game.site.surface_position(cell))
	check(LunarSite.world_cell(game.ground_point(screen)) == cell, "Camera ray must resolve grid cell")
	game.camera_command("Orbit +")
	screen = game.camera_rig.camera.unproject_position(game.site.surface_position(cell))
	check(LunarSite.world_cell(game.ground_point(screen)) == cell, "Orbit must preserve grid mapping")
	game.site.show_preview(cell, false, true)
	check(game.site.preview.visible and game.site.preview.material_override == game.site.bad_material,
		"Invalid construction preview must visibly reject placement")
	for i in range(100):
		game.camera_command("Zoom +")
	check(game.camera_rig.camera.size == 12, "Zoom must respect lower bound")
	for i in range(100):
		game.camera_command("Zoom -")
	check(game.camera_rig.camera.size == 60, "Zoom must respect upper bound")
	var args := OS.get_cmdline_user_args()
	if "--capture" in args and DisplayServer.get_name() != "headless":
		game.restart()
		game.simulation.place("reactor", Vector2i(0, 1))
		game.simulation.place("lab", Vector2i(1, 1))
		game.simulation.place("mine", Vector2i(1, 0))
		game.camera_rig.camera.size = 27
		game.camera_rig.rotation_degrees.y = 45
		game.selected = Vector2i(0, 1)
		game.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		var path := args[args.find("--capture") + 1]
		check(root.get_texture().get_image().save_png(path) == OK, "Render capture must save")
	game.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: scene, HUD, construction, clock, restart, states, supply landings and camera integration")
	quit(1 if failures else 0)


func _visible_rocks(site: LunarSite, cell: Vector2i) -> int:
	var count := 0
	for entry: Array in site.cell_rocks.get(cell, []):
		var transform: Transform3D = entry[0].get_instance_transform(entry[1])
		if transform.basis.get_scale().x > 0.0001 and LunarSite.world_cell(transform.origin) == cell:
			count += 1
	return count


func check_module_visuals(game: ColonyGame) -> void:
	var solar: LunarModule = game.site.models[Vector2i(0, 0)]
	var ice: LunarModule = game.site.models[Vector2i(-3, 0)]
	var oxygen: LunarModule = game.site.models[Vector2i(-2, 0)]
	var habitat: LunarModule = game.site.models[Vector2i(-1, 0)]
	var landing_pad: LunarModule = game.site.models[ColonySimulation.STARTER_LANDING_PAD_CELL]
	var initial_rotation := ice.mechanism.rotation.y
	var initial_tracking := solar.mechanism.rotation.x
	var initial_pump := oxygen.mechanism.position.y
	var initial_beacon := landing_pad.mechanism.rotation.y
	game.advance(0.25)
	check(ice.mechanism.rotation.y != initial_rotation, "Powered extractor must turn its drill")
	check(solar.mechanism.rotation.x != initial_tracking, "Sunlit array must track slowly")
	check(oxygen.mechanism.position.y != initial_pump, "Active life support must stroke its pump")
	check(landing_pad.mechanism.rotation.y != initial_beacon, "Active landing pad must scan its approach beacon")
	check(habitat.glass.emission_energy_multiplier > 0.0, "Supported habitat windows must be lit")
	check(ice.work_light.visible, "Powered service equipment must illuminate its work area")
	game.toggle_pause()
	var paused_rotation := ice.mechanism.rotation.y
	var paused_lamp: Material = ice.lamps[0].material_override
	game.advance(0.25)
	check(ice.mechanism.rotation.y == paused_rotation, "Pause must freeze operating mechanisms")
	check(ice.lamps[0].material_override == paused_lamp, "Pause must freeze telemetry animation")
	game.toggle_pause()
	game.set_speed(4)
	var before := ice.operating_time
	game.advance(0.1)
	check(is_equal_approx(ice.operating_time - before, 0.4), "Animation must follow game speed")
	game.simulation.day = ColonySimulation.DAYLIGHT_DAYS + 1
	game.simulation.day_accumulator = 0.0
	game.simulation.recalculate()
	game.refresh()
	var night_tracking := solar.mechanism.rotation.x
	var night_drill := ice.mechanism.rotation.y
	game.advance(0.1)
	check(not solar.active and not ice.active and not oxygen.active and not habitat.active,
		"Night power loss must reach every starter module's operating state")
	check(solar.mechanism.rotation.x == night_tracking and ice.mechanism.rotation.y == night_drill,
		"Offline solar tracking and extraction must stop")
	check(habitat.glass.emission_energy_multiplier == 0.0, "Offline habitat windows must go dark")
	check(not ice.work_light.visible, "Offline work lights must turn off")
	check(oxygen.lamps.all(func(lamp: MeshInstance3D): return lamp.material_override == oxygen.unlit),
		"Offline equipment must not show running telemetry")
	game.simulation.place("reactor", Vector2i(0, 1))
	var reactor: LunarModule = game.site.models[Vector2i(0, 1)]
	check(reactor.active and ice.active and habitat.active and not solar.active,
		"Night reactor must restore consumers without claiming solar generation")
	for kind in ["link", "lab", "mine", "landing_pad"]:
		var model := LunarModule.new()
		model.build(kind)
		model.set_active(true)
		model.advance(0.25)
		check(model.lamps.size() > 0, "Every module needs operating telemetry: " + kind)
		if kind != "link":
			check(model.mechanism != null, "Production module needs a functional mechanism: " + kind)
		model.free()
	for model: LunarModule in game.site.models.values():
		var bounds := module_bounds(model, model)
		check(_fits_cell(bounds),
			"Detailed hardware must fit its construction cell: " + str(model.get_meta("kind")))
		check(bounds.size.y >= 1.7,
			"Starter and reactor silhouettes must be substantial: " + str(model.get_meta("kind")))
	game.restart()


func check_day_night_fade(game: ColonyGame) -> void:
	game.restart()
	check(is_equal_approx(game.site.sun.light_energy, LunarSite.DAY_ENERGY),
		"New game must start with full daylight energy")
	# Dusk fade: smoothly decrease from DAY_ENERGY to NIGHT_ENERGY across twilight.
	game.simulation.day = ColonySimulation.DAYLIGHT_DAYS - 1
	game.simulation.day_accumulator = 0.5
	game.refresh()
	var prev_energy := game.site.sun.light_energy
	check(is_equal_approx(prev_energy, LunarSite.DAY_ENERGY),
		"Dusk start must still be at full daylight energy")
	var saw_intermediate := false
	for i in range(24):
		game.advance(0.25)
		var energy := game.site.sun.light_energy
		check(energy <= prev_energy + 0.0001, "Dusk lighting must fade monotonically downward")
		if energy < LunarSite.DAY_ENERGY - 0.1 and energy > LunarSite.NIGHT_ENERGY + 0.1:
			saw_intermediate = true
		prev_energy = energy
	check(saw_intermediate, "Dusk transition must pass through intermediate faded lighting")
	check(is_equal_approx(game.site.sun.light_energy, LunarSite.NIGHT_ENERGY),
		"Dusk transition must settle at night lighting energy")
	# Pause must freeze twilight mid-transition.
	game.simulation.day = ColonySimulation.CYCLE_DAYS
	game.simulation.day_accumulator = 0.25
	game.refresh()
	var mid_dawn_energy := game.site.sun.light_energy
	check(mid_dawn_energy > LunarSite.NIGHT_ENERGY + 0.1 and mid_dawn_energy < LunarSite.DAY_ENERGY - 0.1,
		"Dawn midpoint must render intermediate lighting")
	game.toggle_pause()
	game.advance(0.25)
	check(is_equal_approx(game.site.sun.light_energy, mid_dawn_energy),
		"Pause must freeze day/night lighting transition")
	game.toggle_pause()
	# Dawn fade: smoothly increase back to DAY_ENERGY at sunrise.
	prev_energy = game.site.sun.light_energy
	for i in range(12):
		game.advance(0.25)
		var energy := game.site.sun.light_energy
		check(energy >= prev_energy - 0.0001, "Dawn lighting must fade monotonically upward")
		prev_energy = energy
	check(is_equal_approx(game.site.sun.light_energy, LunarSite.DAY_ENERGY),
		"Dawn transition must settle back at full daylight energy")
	game.restart()


func check_structure_states(game: ColonyGame) -> void:
	# Verify shared construction (0%, 50%, 100%), damaged and repairing states across ALL catalog kinds.
	for kind in BuildingCatalog.ORDER:
		var model := LunarModule.new()
		game.site.add_child(model)
		model.build(kind)
		model.set_active(true)
		var pristine_white_v := model.white.albedo_color.v

		# 0% build progress: foundation visible, primary body hidden, construction rig shown.
		model.set_build_progress(0.0)
		check(model.foundation_root.visible and model.construction_rig.visible,
			"0%% construction must show foundation and construction rig: " + kind)
		check(not model.damage_rig.visible and not model.repair_rig.visible,
			"Construction state must hide damage/repair rigs: " + kind)
		var visible_at_0 := _count_visible_body_parts(model)
		check(visible_at_0 == 0, "0%% construction must hide primary body parts: " + kind)
		check(_fits_cell(module_bounds(model, model)),
			"0%% construction state must fit cell footprint: " + kind)

		# 50% build progress: progressive reveal + crane arm moves when advancing.
		model.set_build_progress(0.5)
		var visible_at_50 := _count_visible_body_parts(model)
		check(visible_at_50 > 0 and visible_at_50 < model._body_parts.size(),
			"50%% construction must partially reveal primary form: " + kind)
		var crane_before := model.construction_arm.rotation.y
		model.advance(0.25)
		check(model.construction_arm.rotation.y != crane_before,
			"Construction crane arm must animate while building: " + kind)
		check(_fits_cell(module_bounds(model, model)),
			"50%% construction state must fit cell footprint: " + kind)

		# 100% build progress: complete form shown, construction rig hidden.
		model.set_build_progress(1.0)
		check(not model.construction_rig.visible, "100%% build must hide construction rig: " + kind)
		check(_count_visible_body_parts(model) == model._body_parts.size(),
			"100%% build must reveal all body parts: " + kind)

		# Damaged state: dust-darkened surface + non-color bent panel & hazard placard + warning lamps.
		model.set_condition(ColonySimulation.CONDITION_DAMAGED)
		check(model.damage_rig.visible and model.hazard_placard.visible and model.bent_panel.visible,
			"Damaged state must display non-color hazard placard and bent panel: " + kind)
		check(model.white.albedo_color.v < pristine_white_v - 0.1,
			"Damaged state must dust-darken structure surfaces: " + kind)
		model.advance(0.35)
		check(_fits_cell(module_bounds(model, model)),
			"Damaged state must fit cell footprint: " + kind)

		# Repairing state: repair arm active + progress segments + EVA tool rack.
		model.set_condition(ColonySimulation.CONDITION_REPAIRING, 0.6)
		check(model.repair_rig.visible and not model.damage_rig.visible,
			"Repairing state must show repair rig and hide damage rig: " + kind)
		var arm_before := model.repair_arm.rotation.y
		model.advance(0.25)
		check(model.repair_arm.rotation.y != arm_before,
			"Repair arm must articulate during repair: " + kind)
		check(model.repair_segments[0].material_override == model.repair_lit
			and model.repair_segments[4].material_override == model.unlit,
			"Repair progress strip must reflect partial progress: " + kind)
		check(_fits_cell(module_bounds(model, model)),
			"Repairing state must fit cell footprint: " + kind)

		# Repaired back to operational: overlays hidden and pristine surface restored.
		model.set_condition(ColonySimulation.CONDITION_OPERATIONAL)
		check(not model.damage_rig.visible and not model.repair_rig.visible,
			"Operational state must hide damage and repair rigs: " + kind)
		check(is_equal_approx(model.white.albedo_color.v, pristine_white_v),
			"Operational state must restore clean surface color: " + kind)
		check(_fits_cell(module_bounds(model, model)),
			"Operational state must fit cell footprint: " + kind)
		model.free()

	# Authoritative simulation driving scene visuals + pause freeze + HUD text status.
	var hab_cell := Vector2i(-1, 0)
	var hab_model: LunarModule = game.site.models[hab_cell]
	game.simulation.set_building_build_progress(hab_cell, 0.5)
	game.activate_cell(hab_cell)
	check(hab_model.construction_rig.visible, "Simulation build_progress must drive LunarModule visuals")
	check("UNDER CONSTRUCTION" in game.hud.inspector.text, "Inspector must report construction state")
	game.toggle_pause()
	var paused_crane := hab_model.construction_arm.rotation.y
	game.advance(0.25)
	check(hab_model.construction_arm.rotation.y == paused_crane, "Pause must freeze construction arm")
	game.toggle_pause()

	game.simulation.set_building_build_progress(hab_cell, 1.0)
	game.simulation.set_building_condition(hab_cell, ColonySimulation.CONDITION_DAMAGED)
	game.activate_cell(hab_cell)
	check(hab_model.damage_rig.visible, "Simulation damaged condition must drive LunarModule visuals")
	check("DAMAGED" in game.hud.inspector.text, "Inspector must report damaged state without color")
	game.toggle_pause()
	var paused_state_time := hab_model.state_time
	game.advance(0.25)
	check(hab_model.state_time == paused_state_time, "Pause must freeze damaged warning pattern")
	game.toggle_pause()

	game.simulation.set_building_condition(hab_cell, ColonySimulation.CONDITION_REPAIRING, 0.6)
	game.activate_cell(hab_cell)
	check(hab_model.repair_rig.visible, "Simulation repairing condition must drive LunarModule visuals")
	check("UNDER REPAIR" in game.hud.inspector.text, "Inspector must report repair progress")
	game.toggle_pause()
	var paused_repair := hab_model.repair_arm.rotation.y
	game.advance(0.25)
	check(hab_model.repair_arm.rotation.y == paused_repair, "Pause must freeze repair arm")
	game.toggle_pause()
	game.restart()


func check_landing_pad_and_supply_ships(game: ColonyGame) -> void:
	var pad_cell := ColonySimulation.STARTER_LANDING_PAD_CELL
	check(game.site.models.has(pad_cell) and game.site.landers.has(pad_cell),
		"Scene must spawn starter landing pad and its supply lander")
	var lander: SupplyLander = game.site.landers[pad_cell]
	check(lander.visible and lander.current_phase == "approaching",
		"Starter supply lander must be visible on approach at new game")
	check("Supplies 0 t" in game.hud.stats.text, "HUD must display initial supply stockpile")
	check("Next landing:" in game.hud.logistics.text, "HUD must display delivery timing")

	# Pause freezes ship position and supply accounting.
	game.toggle_pause()
	var paused_y := lander.craft.position.y
	game.advance(0.25)
	check(lander.craft.position.y == paused_y and game.simulation.supplies == 0.0,
		"Pause must freeze lander motion and deliveries")
	game.toggle_pause()

	# Advance smoothly through approach and descent -> ship visibly descends before credit.
	var y_start := lander.craft.position.y
	for i in range(24):
		game.advance(0.25)
	check(lander.craft.position.y < y_start, "Supply ship must visibly descend toward the pad")
	check(game.simulation.supplies == 0.0, "No supply may be credited while ship is still descending")

	# Advance into delivering on deck (y == DECK_Y), then complete offload for exactly 1 credit.
	for i in range(16):
		game.advance(0.20)
	check(is_equal_approx(game.simulation.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Completed landing must credit one supply shipment")
	check("Supplies 4 t" in game.hud.stats.text, "HUD must update supply stockpile after delivery")
	check(lander.current_phase == "departing", "Lander must depart after delivery completes")
	var y_depart := lander.craft.position.y
	game.advance(0.25)
	check(lander.craft.position.y > y_depart, "Departing lander must visibly climb away from pad")
	check(is_equal_approx(game.simulation.supplies, ColonySimulation.SUPPLY_DELIVERY_AMOUNT),
		"Departure motion must not double-credit supplies")

	# Large background gap is clamped to 0.25s * speed (no phantom multi-delivery burst).
	var supplies_before_gap := game.simulation.supplies
	game.set_speed(4)
	game.advance(120.0)
	check(is_equal_approx(game.simulation.supplies, supplies_before_gap),
		"Large background gap must be clamped and not trigger phantom deliveries")

	# Simultaneous landing pads must have independent landers and scale deliveries cleanly.
	var pad2_cell := Vector2i(3, -2)
	check(game.simulation.place("landing_pad", pad2_cell), "Constructing second landing pad must succeed")
	check(game.site.landers.size() == 2, "Second landing pad must get its own SupplyLander instance")
	check(game.site.landers[pad_cell] != game.site.landers[pad2_cell],
		"Pads must not share mutable lander instances")
	check("Supply pads: 2 active" in game.hud.logistics.text, "HUD must show active pad count")

	# Demolishing second pad removes its lander cleanly without stranding ships.
	game.simulation.demolish(pad2_cell)
	await process_frame
	check(game.site.landers.size() == 1 and not game.site.landers.has(pad2_cell),
		"Demolishing a landing pad must remove its SupplyLander")

	# Restart restores single starter pad, 0 supplies, and visible approaching ship.
	game.restart()
	await process_frame
	check(game.site.landers.size() == 1 and game.site.landers[pad_cell].visible
		and game.site.landers[pad_cell].current_phase == "approaching",
		"Restart must restore starter landing pad and approaching supply ship")
	check(game.simulation.supplies == 0.0, "Restart must reset supplies to 0")


func _count_visible_body_parts(model: LunarModule) -> int:
	var count := 0
	for entry: Dictionary in model._body_parts:
		if (entry["node"] as Node3D).visible:
			count += 1
	return count


func _fits_cell(bounds: AABB) -> bool:
	return (
		bounds.position.x >= -LunarSite.CELL_SIZE * 0.5 - 0.001
		and bounds.end.x <= LunarSite.CELL_SIZE * 0.5 + 0.001
		and bounds.position.z >= -LunarSite.CELL_SIZE * 0.5 - 0.001
		and bounds.end.z <= LunarSite.CELL_SIZE * 0.5 + 0.001
	)


func module_bounds(node: Node3D, model: LunarModule) -> AABB:
	var bounds := AABB()
	if node is MeshInstance3D:
		var transform := model.global_transform.affine_inverse() * node.global_transform
		bounds = transform * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			bounds = bounds.merge(module_bounds(child, model))
	return bounds
