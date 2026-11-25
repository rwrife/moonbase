class_name LunarModule
extends Node3D

const SURFACE_SHADER := preload("res://shaders/module_surface.gdshader")
const DUST_COLOR := Color(0.23, 0.22, 0.20)

var active := false
var operating_time := 0.0
var state_time := 0.0
var build_progress := 1.0
var condition := ColonySimulation.CONDITION_OPERATIONAL
var repair_progress := 1.0

var foundation_root: Node3D
var body_root: Node3D
var construction_rig: Node3D
var construction_arm: Node3D
var construction_carriage: Node3D
var construction_tiers: Array[Node3D] = []
var construction_segments: Array[MeshInstance3D] = []
var damage_rig: Node3D
var hazard_placard: Node3D
var bent_panel: Node3D
var warning_lamps: Array[MeshInstance3D] = []
var repair_rig: Node3D
var repair_arm: Node3D
var repair_segments: Array[MeshInstance3D] = []
var _body_parts: Array[Dictionary] = []
var _rig_height := 1.8

var mechanism: Node3D
var status: MeshInstance3D
var lamps: Array[MeshInstance3D] = []
var windows: Array[MeshInstance3D] = []
var work_light: OmniLight3D
var silver: StandardMaterial3D
var white: StandardMaterial3D
var dark: StandardMaterial3D
var gold: ShaderMaterial
var blue: ShaderMaterial
var accent: StandardMaterial3D
var lit: StandardMaterial3D
var unlit: StandardMaterial3D
var warn_lit: StandardMaterial3D
var warn_unlit: StandardMaterial3D
var repair_lit: StandardMaterial3D
var glass: StandardMaterial3D
var status_material: StandardMaterial3D
var _base_colors: Dictionary = {}
var _base_roughness: Dictionary = {}


func build(kind: String) -> void:
	set_meta("kind", kind)
	silver = _material(Color(0.57, 0.61, 0.65), 0.8, 0.32)
	white = _material(Color(0.86, 0.87, 0.84), 0.15, 0.6)
	dark = _material(Color(0.055, 0.067, 0.08), 0.5, 0.75)
	accent = _material(BuildingCatalog.definition(kind)["color"], 0.25, 0.5)
	gold = ShaderMaterial.new()
	gold.shader = SURFACE_SHADER
	gold.set_shader_parameter("base_color", Color(0.72, 0.52, 0.22))
	blue = ShaderMaterial.new()
	blue.shader = SURFACE_SHADER
	blue.set_shader_parameter("solar_cells", true)
	blue.set_shader_parameter("base_color", Color(0.025, 0.075, 0.19))
	lit = _material(Color(0.32, 0.8, 0.67), 0.0, 0.4)
	lit.emission_enabled = true
	lit.emission = Color(0.12, 0.65, 0.42)
	lit.emission_energy_multiplier = 1.8
	unlit = _material(Color(0.07, 0.12, 0.12))
	warn_lit = _material(Color(0.95, 0.72, 0.18), 0.0, 0.35)
	warn_lit.emission_enabled = true
	warn_lit.emission = Color(0.95, 0.55, 0.08)
	warn_lit.emission_energy_multiplier = 2.2
	warn_unlit = _material(Color(0.16, 0.12, 0.08))
	repair_lit = _material(Color(0.32, 0.78, 0.96), 0.0, 0.35)
	repair_lit.emission_enabled = true
	repair_lit.emission = Color(0.18, 0.64, 0.92)
	repair_lit.emission_energy_multiplier = 1.9
	glass = _material(Color(0.035, 0.07, 0.1), 0.6, 0.2)
	glass.emission_enabled = true
	status_material = _material(Color(0.8, 0.19, 0.07))
	status_material.emission_enabled = true
	status_material.emission = Color(0.8, 0.09, 0.025)

	_base_colors = {
		"silver": silver.albedo_color,
		"white": white.albedo_color,
		"accent": accent.albedo_color,
		"gold": Color(0.72, 0.52, 0.22),
		"blue": Color(0.025, 0.075, 0.19),
	}
	_base_roughness = {
		"silver": silver.roughness,
		"white": white.roughness,
		"accent": accent.roughness,
	}

	foundation_root = Node3D.new()
	foundation_root.name = "Foundation"
	add_child(foundation_root)
	body_root = Node3D.new()
	body_root.name = "PrimaryStructure"
	add_child(body_root)

	_foundation(kind)
	match kind:
		"habitat", "lab":
			_pressure_module(kind)
		"solar":
			_solar_array()
		"ice", "oxygen":
			_processing_module(kind)
		"reactor":
			_reactor()
		"mine":
			_refinery()
		"link":
			_utility_link()
		"landing_pad":
			_landing_pad()

	var status_y := 0.24 if kind == "landing_pad" else 0.46
	status = _box(self, Vector3(0.24, 0.045, 0.1), Vector3(0, status_y, 1.06),
		status_material)
	status.name = "OperatingStatus"
	if kind != "link":
		var fixture_at := Vector3(-0.74, 1.52, -0.74) if kind == "landing_pad" else Vector3(0.78, 1.5, 0.85)
		_box(body_root, Vector3(0.13, 0.08, 0.12), fixture_at, dark)
		_box(body_root, Vector3(0.09, 0.025, 0.08),
			fixture_at + Vector3(0, -0.045, 0.02), glass)
		work_light = OmniLight3D.new()
		work_light.name = "ServiceLight"
		work_light.position = fixture_at + Vector3(0, -0.12, 0.12)
		work_light.light_color = Color(1.0, 0.83, 0.59)
		work_light.light_energy = 0.45
		work_light.omni_range = 2.4
		body_root.add_child(work_light)

	_collect_body_parts()
	_build_state_overlays(kind)
	build_progress = 1.0
	condition = ColonySimulation.CONDITION_OPERATIONAL
	repair_progress = 1.0
	active = false
	_apply_visual_state(true)


func set_active(value: bool) -> void:
	var was_active := active
	active = value
	_apply_visual_state(not active or not was_active)


func set_build_progress(progress: float) -> void:
	var clamped := clampf(progress, 0.0, 1.0)
	if is_equal_approx(build_progress, clamped):
		return
	build_progress = clamped
	_apply_visual_state(true)


func set_condition(state: String, new_repair_progress: float = -1.0) -> void:
	var next_condition := state if (state in ColonySimulation.VALID_CONDITIONS) else condition
	var next_repair := repair_progress
	if next_condition == ColonySimulation.CONDITION_OPERATIONAL:
		next_repair = 1.0
	elif next_condition == ColonySimulation.CONDITION_DAMAGED:
		next_repair = 0.0
	elif new_repair_progress >= 0.0:
		next_repair = clampf(new_repair_progress, 0.0, 1.0)
	if next_condition == condition and is_equal_approx(next_repair, repair_progress):
		return
	var condition_changed := next_condition != condition
	condition = next_condition
	repair_progress = next_repair
	_apply_visual_state(condition_changed)


func set_repair_progress(progress: float) -> void:
	var clamped := clampf(progress, 0.0, 1.0)
	if is_equal_approx(repair_progress, clamped):
		return
	repair_progress = clamped
	_apply_visual_state(false)


func _is_operational_visual() -> bool:
	return build_progress >= 1.0 and condition == ColonySimulation.CONDITION_OPERATIONAL


func _apply_visual_state(reset_lamps: bool) -> void:
	var under_construction := build_progress < 1.0
	var damaged := not under_construction and condition == ColonySimulation.CONDITION_DAMAGED
	var repairing := not under_construction and condition == ColonySimulation.CONDITION_REPAIRING
	var operational_active := active and _is_operational_visual()

	# Progressive reveal of primary body parts from foundation upward.
	for entry: Dictionary in _body_parts:
		var node: Node3D = entry["node"]
		var threshold: float = entry["threshold"]
		node.visible = (not under_construction) or (build_progress >= threshold)

	# Construction rig visibility, truss tiers, crane elevation and progress strip.
	if construction_rig != null:
		construction_rig.visible = under_construction
		if under_construction:
			for i in range(construction_tiers.size()):
				var tier_threshold := float(i) / float(maxi(1, construction_tiers.size()))
				construction_tiers[i].visible = build_progress >= tier_threshold * 0.85
			if construction_carriage != null:
				construction_carriage.position.y = lerpf(0.38, maxf(0.56, _rig_height - 0.14), build_progress)
			_update_segment_strip(construction_segments, build_progress, warn_lit)

	# Damage rig visibility (non-color bent panel, hazard placard, twin strobe post).
	if damage_rig != null:
		damage_rig.visible = damaged

	# Repair rig visibility (repair arm, EVA tool rack, segmented progress bar).
	if repair_rig != null:
		repair_rig.visible = repairing
		if repairing:
			_update_segment_strip(repair_segments, repair_progress, repair_lit)

	# Dust darkening on shared structure materials.
	var wear := 0.0
	if damaged:
		wear = 1.0
	elif repairing:
		wear = clampf(1.0 - repair_progress * 0.85, 0.15, 1.0)
	_update_surface_wear(wear)

	# Status indicator, windows, work light and telemetry lamps.
	if under_construction:
		status_material.albedo_color = Color(0.92, 0.72, 0.24)
		status_material.emission = Color(0.78, 0.54, 0.12)
		status_material.emission_energy_multiplier = 1.1
	elif damaged:
		status_material.albedo_color = Color(0.92, 0.24, 0.08)
		status_material.emission = Color(0.85, 0.16, 0.04)
		status_material.emission_energy_multiplier = 1.4
	elif repairing:
		status_material.albedo_color = Color(0.28, 0.74, 0.95)
		status_material.emission = Color(0.16, 0.56, 0.85)
		status_material.emission_energy_multiplier = 1.3
	else:
		status_material.albedo_color = Color(0.19, 0.8, 0.5) if operational_active else Color(0.8, 0.19, 0.07)
		status_material.emission = Color(0.08, 0.55, 0.28) if operational_active else Color(0.6, 0.06, 0.015)
		status_material.emission_energy_multiplier = 1.4 if operational_active else 0.6

	glass.emission = Color(0.8, 0.48, 0.18) if operational_active else Color.BLACK
	glass.emission_energy_multiplier = 0.65 if operational_active else 0.0
	if work_light != null:
		work_light.visible = operational_active

	if reset_lamps:
		for lamp in lamps:
			lamp.material_override = lit if operational_active else unlit
		for i in range(warning_lamps.size()):
			warning_lamps[i].material_override = warn_lit if (damaged and i == 0) else warn_unlit


func _update_surface_wear(wear: float) -> void:
	if _base_colors.is_empty():
		return
	white.albedo_color = (_base_colors["white"] as Color).lerp(DUST_COLOR, wear * 0.62)
	silver.albedo_color = (_base_colors["silver"] as Color).lerp(DUST_COLOR, wear * 0.58)
	accent.albedo_color = (_base_colors["accent"] as Color).lerp(DUST_COLOR, wear * 0.52)
	white.roughness = lerpf(float(_base_roughness["white"]), 0.94, wear)
	silver.roughness = lerpf(float(_base_roughness["silver"]), 0.86, wear)
	accent.roughness = lerpf(float(_base_roughness["accent"]), 0.90, wear)
	gold.set_shader_parameter("base_color", (_base_colors["gold"] as Color).lerp(DUST_COLOR, wear * 0.58))
	blue.set_shader_parameter("base_color", (_base_colors["blue"] as Color).lerp(DUST_COLOR, wear * 0.55))


func _update_segment_strip(segments: Array[MeshInstance3D], progress: float,
		active_mat: Material) -> void:
	var count := segments.size()
	if count == 0:
		return
	var filled := int(round(clampf(progress, 0.0, 1.0) * float(count)))
	for i in range(count):
		var on := i < filled
		segments[i].material_override = active_mat if on else unlit
		segments[i].scale.y = 1.25 if on else 0.72


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if build_progress < 1.0:
		state_time += delta
		if construction_arm != null:
			# Crane boom sweeps inward over the structure; stays strictly within cell bounds.
			construction_arm.rotation.y = sin(state_time * 1.15) * 0.42
		return
	if condition == ColonySimulation.CONDITION_DAMAGED:
		state_time += delta
		# Double-pulse warning lamp pattern (distinct from normal chasing telemetry).
		var cycle := fposmod(state_time * 2.4, 2.0)
		var pulse_a := (cycle < 0.28) or (cycle >= 0.48 and cycle < 0.76)
		var pulse_b := (cycle >= 1.0 and cycle < 1.28) or (cycle >= 1.48 and cycle < 1.76)
		for i in range(warning_lamps.size()):
			var on := pulse_a if (i % 2 == 0) else pulse_b
			warning_lamps[i].material_override = warn_lit if on else warn_unlit
		# Deterministic erratic telemetry flicker.
		for i in range(lamps.size()):
			var flicker := sin(state_time * 17.0 + float(i) * 2.7) * cos(state_time * 9.3 - float(i))
			lamps[i].material_override = warn_lit if flicker > 0.58 else unlit
		status_material.emission_energy_multiplier = 2.0 if (pulse_a or pulse_b) else 0.35
		return
	if condition == ColonySimulation.CONDITION_REPAIRING:
		state_time += delta
		if repair_arm != null:
			repair_arm.rotation.y = sin(state_time * 1.4) * 0.36
			repair_arm.rotation.x = sin(state_time * 2.1) * 0.10
		return
	if not active:
		return
	operating_time += delta
	var kind: String = get_meta("kind")
	if mechanism != null:
		match kind:
			"solar":
				# Slow bounded tracking, not a spinning array or a lunar wind effect.
				mechanism.rotation.x = -0.22 + sin(operating_time * 0.12) * 0.12
			"ice":
				mechanism.rotation.y = operating_time * 2.5
			"oxygen":
				mechanism.position.y = 1.06 + sin(operating_time * 3.0) * 0.065
			"habitat", "lab":
				mechanism.rotation.y = sin(operating_time * 0.35) * 0.65
			"mine":
				mechanism.rotation.x = operating_time * 1.8
			"landing_pad":
				mechanism.rotation.y = sin(operating_time * 0.55) * 0.85
	for i in range(lamps.size()):
		var on := fposmod(operating_time * 2.0 - float(i) * 0.35, 2.0) < 1.0
		lamps[i].material_override = lit if on else unlit


func _collect_body_parts() -> void:
	_body_parts.clear()
	var nodes: Array[Node3D] = []
	_gather_visual_nodes(body_root, nodes)
	if nodes.is_empty():
		_rig_height = 1.6
		return
	var min_y := 1e6
	var max_y := -1e6
	var centers: Array[float] = []
	for node in nodes:
		var local_pos := _relative_position(node, body_root)
		var top_y := local_pos.y
		var bot_y := local_pos.y
		if node is MeshInstance3D:
			var aabb := (node as MeshInstance3D).get_aabb()
			bot_y = local_pos.y + aabb.position.y
			top_y = local_pos.y + aabb.end.y
		min_y = minf(min_y, bot_y)
		max_y = maxf(max_y, top_y)
		centers.append((bot_y + top_y) * 0.5)
	_rig_height = clampf(max_y + 0.12, 0.72, 2.45)
	var span := maxf(max_y - min_y, 0.25)
	var order: Array[int] = []
	for i in range(nodes.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return centers[a] < centers[b])
	var total := float(maxi(1, order.size()))
	for rank in range(order.size()):
		var idx := order[rank]
		var height_frac := clampf((centers[idx] - min_y) / span, 0.0, 1.0)
		var rank_frac := float(rank) / total
		var threshold := lerpf(0.05, 0.96, height_frac * 0.65 + rank_frac * 0.35)
		_body_parts.append({"node": nodes[idx], "threshold": threshold})


func _gather_visual_nodes(parent: Node3D, out: Array[Node3D]) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D or child is Label3D:
			out.append(child)
		elif child is Node3D:
			_gather_visual_nodes(child, out)


func _relative_position(node: Node3D, ancestor: Node3D) -> Vector3:
	var pos := node.position
	var current := node.get_parent()
	while current != null and current != ancestor and current is Node3D:
		pos = (current as Node3D).transform * pos
		current = current.get_parent()
	return pos


func _build_state_overlays(kind: String) -> void:
	var compact := kind == "link"
	var cage_half := 0.90 if compact else 0.98
	var cage_h := 0.74 if compact else clampf(_rig_height, 1.55, 2.35)

	# 1. Shared construction truss cage + working crane arm + progress strip.
	construction_rig = Node3D.new()
	construction_rig.name = "ConstructionRig"
	add_child(construction_rig)
	for x in [-cage_half, cage_half]:
		for z in [-cage_half, cage_half]:
			_cylinder(construction_rig, 0.032, cage_h, Vector3(x, cage_h * 0.5 + 0.08, z), silver)
	var tier_count := 2 if compact else 3
	for t in range(tier_count):
		var tier := Node3D.new()
		tier.name = "TrussTier%d" % t
		construction_rig.add_child(tier)
		var y := lerpf(0.32, cage_h + 0.04, float(t + 1) / float(tier_count))
		for side in [-cage_half, cage_half]:
			_box(tier, Vector3(cage_half * 2.0, 0.035, 0.035), Vector3(0, y, side), silver)
			_box(tier, Vector3(0.035, 0.035, cage_half * 2.0), Vector3(side, y, 0), silver)
		if t == 0:
			_strut(tier, Vector3(-cage_half, 0.14, -cage_half), Vector3(cage_half, y, -cage_half), 0.018, accent)
			_strut(tier, Vector3(-cage_half, 0.14, cage_half), Vector3(cage_half, y, cage_half), 0.018, accent)
		construction_tiers.append(tier)

	# Crane carriage rides the back-left corner post and sweeps inward toward center.
	construction_carriage = Node3D.new()
	construction_carriage.name = "CraneCarriage"
	construction_carriage.position = Vector3(-cage_half, 0.5, -cage_half)
	construction_rig.add_child(construction_carriage)
	_box(construction_carriage, Vector3(0.14, 0.14, 0.14), Vector3.ZERO, dark)
	construction_arm = Node3D.new()
	construction_arm.name = "ConstructionCraneArm"
	construction_carriage.add_child(construction_arm)
	var boom_end := Vector3(0.62, 0.04, 0.62)
	_strut(construction_arm, Vector3.ZERO, boom_end, 0.028, accent)
	_strut(construction_arm, Vector3(0, 0.12, 0), boom_end * 0.72 + Vector3(0, 0.04, 0), 0.016, silver)
	_box(construction_arm, Vector3(0.12, 0.10, 0.12), boom_end + Vector3(0, -0.08, 0), dark)
	_box(construction_arm, Vector3(0.06, 0.05, 0.06), boom_end + Vector3(0, -0.15, 0), warn_lit)

	var build_bar_y := 0.34 if compact else 0.56
	_box(construction_rig, Vector3(0.74, 0.12, 0.05), Vector3(0, build_bar_y, 1.03), dark)
	for i in range(5):
		var seg := _box(construction_rig, Vector3(0.10, 0.06, 0.04),
			Vector3(-0.26 + float(i) * 0.13, build_bar_y, 1.055), warn_lit)
		construction_segments.append(seg)
	_label_on(construction_rig, "BUILD", Vector3(0, build_bar_y + 0.11, 1.04), 22, Color(0.95, 0.84, 0.42))

	# 2. Shared damage overlay: bent panel, high-contrast non-color hazard placard, twin strobe post.
	damage_rig = Node3D.new()
	damage_rig.name = "DamageRig"
	add_child(damage_rig)

	bent_panel = Node3D.new()
	bent_panel.name = "BentPanel"
	bent_panel.position = Vector3(-0.56, 0.36 if compact else 0.86, 0.84)
	bent_panel.rotation_degrees = Vector3(14.0, -22.0, 28.0)
	damage_rig.add_child(bent_panel)
	_box(bent_panel, Vector3(0.42, 0.28, 0.035), Vector3.ZERO, dark)
	_box(bent_panel, Vector3(0.38, 0.24, 0.04), Vector3(0.01, 0.01, 0.008), silver)
	_strut(bent_panel, Vector3(-0.18, -0.10, -0.02), Vector3(0.18, 0.10, 0.04), 0.014, dark)

	hazard_placard = Node3D.new()
	hazard_placard.name = "HazardPlacard"
	hazard_placard.position = Vector3(0.0, 0.42 if compact else 0.78, 1.03)
	hazard_placard.rotation_degrees.x = -14.0
	damage_rig.add_child(hazard_placard)
	# Dedicated clean high-contrast placard material so ! FAULT pops against dust-darkened hull.
	var placard_face := _material(Color(0.95, 0.94, 0.90), 0.0, 0.45)
	placard_face.emission_enabled = true
	placard_face.emission = Color(0.28, 0.26, 0.22)
	placard_face.emission_energy_multiplier = 0.45
	_box(hazard_placard, Vector3(0.66, 0.32, 0.04), Vector3.ZERO, dark)
	_box(hazard_placard, Vector3(0.58, 0.24, 0.045), Vector3(0, 0, 0.006), placard_face)
	for sx in [-0.22, -0.11, 0.0, 0.11, 0.22]:
		var stripe := _box(hazard_placard, Vector3(0.045, 0.09, 0.05), Vector3(sx, -0.085, 0.01), dark)
		stripe.rotation_degrees.z = -28.0
	_label_on(hazard_placard, "! FAULT", Vector3(0, 0.035, 0.035), 24, Color(0.04, 0.04, 0.05))

	var post_h := 0.62 if compact else 1.38
	_cylinder(damage_rig, 0.028, post_h, Vector3(0.86, post_h * 0.5 + 0.08, 0.86), dark)
	_box(damage_rig, Vector3(0.14, 0.16, 0.12), Vector3(0.86, post_h + 0.06, 0.86), dark)
	for offset_y in [-0.04, 0.04]:
		var wlamp := _box(damage_rig, Vector3(0.16, 0.05, 0.14),
			Vector3(0.86, post_h + 0.06 + offset_y, 0.86), warn_lit)
		warning_lamps.append(wlamp)
	var fault_light := OmniLight3D.new()
	fault_light.name = "FaultBeaconLight"
	fault_light.position = Vector3(0.58, post_h + 0.10, 0.96)
	fault_light.light_color = Color(1.0, 0.68, 0.32)
	fault_light.light_energy = 0.35
	fault_light.omni_range = 2.0
	damage_rig.add_child(fault_light)

	# 3. Shared repair overlay: articulated repair arm, EVA tool rack prop, progress segment strip.
	repair_rig = Node3D.new()
	repair_rig.name = "RepairRig"
	add_child(repair_rig)

	# Articulated repair arm on front-left pad edge, reaching inward.
	var arm_base_y := 0.22 if compact else 0.30
	_cylinder(repair_rig, 0.10, 0.16, Vector3(-0.78, arm_base_y, 0.78), dark)
	repair_arm = Node3D.new()
	repair_arm.name = "RepairArm"
	repair_arm.position = Vector3(-0.78, arm_base_y + 0.08, 0.78)
	repair_rig.add_child(repair_arm)
	var elbow := Vector3(0.20, 0.44 if not compact else 0.24, -0.22)
	var wrist := Vector3(0.46, 0.54 if not compact else 0.28, -0.44)
	_strut(repair_arm, Vector3.ZERO, elbow, 0.028, silver)
	_box(repair_arm, Vector3(0.08, 0.08, 0.08), elbow, accent)
	_strut(repair_arm, elbow, wrist, 0.022, silver)
	_box(repair_arm, Vector3(0.09, 0.07, 0.09), wrist, dark)
	_box(repair_arm, Vector3(0.045, 0.045, 0.045), wrist + Vector3(0.03, 0, -0.03), repair_lit)
	var repair_light := OmniLight3D.new()
	repair_light.name = "RepairWorkLight"
	repair_light.position = wrist + Vector3(0.06, 0.12, 0.18)
	repair_light.light_color = Color(0.76, 0.90, 1.0)
	repair_light.light_energy = 0.40
	repair_light.omni_range = 2.2
	repair_arm.add_child(repair_light)

	# EVA tool rack prop on front-right pad edge.
	var rack := Node3D.new()
	rack.name = "EVAToolRack"
	rack.position = Vector3(0.80, 0.34 if compact else 0.48, 0.78)
	repair_rig.add_child(rack)
	for rx in [-0.14, 0.14]:
		_cylinder(rack, 0.022, 0.48, Vector3(rx, 0, 0), silver)
	_box(rack, Vector3(0.32, 0.04, 0.18), Vector3(0, -0.18, 0), dark)
	_box(rack, Vector3(0.32, 0.035, 0.14), Vector3(0, 0.18, 0), silver)
	for tx in [-0.09, 0.0, 0.09]:
		_cylinder(rack, 0.026, 0.24, Vector3(tx, 0.0, 0.02), white if tx != 0.0 else accent)

	# Progress segment strip on +Z front.
	var rep_bar_y := 0.36 if compact else 0.62
	_box(repair_rig, Vector3(0.76, 0.14, 0.055), Vector3(0, rep_bar_y, 1.03), dark)
	for i in range(5):
		var seg := _box(repair_rig, Vector3(0.105, 0.07, 0.045),
			Vector3(-0.26 + float(i) * 0.13, rep_bar_y, 1.058), repair_lit)
		repair_segments.append(seg)
	_label_on(repair_rig, "REPAIR", Vector3(0, rep_bar_y + 0.12, 1.04), 22, Color(0.55, 0.88, 1.0))


func _material(color: Color, metallic: float = 0.0,
		roughness: float = 0.7) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, at, material)


func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3,
		material: Material, top_ratio: float = 1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius * top_ratio
	mesh.height = height
	mesh.radial_segments = 32
	return _mesh(parent, mesh, at, material)


func _strut(parent: Node3D, start: Vector3, end: Vector3, radius: float,
		material: Material) -> MeshInstance3D:
	var rod := _cylinder(parent, radius, start.distance_to(end), (start + end) * 0.5, material)
	rod.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return rod


func _label(text: String, at: Vector3, size: int = 40) -> void:
	_label_on(body_root, text, at, size, Color(0.12, 0.18, 0.24))


func _label_on(parent: Node3D, text: String, at: Vector3, size: int,
		color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.position = at
	label.modulate = color
	label.outline_size = 0
	parent.add_child(label)


func _foundation(kind: String) -> void:
	if kind == "link":
		for direction in ColonySimulation.NEIGHBORS:
			var end := Vector3(direction.x, 0, direction.y) * 1.12
			for fraction in [0.35, 0.65, 0.88]:
				_box(foundation_root, Vector3(0.32, 0.05, 0.32),
					end * fraction + Vector3(0, 0.15, 0), dark)
		return
	if kind == "landing_pad":
		_box(foundation_root, Vector3(2.18, 0.12, 2.18), Vector3(0, 0.08, 0), dark)
		for x in [-0.90, 0.90]:
			for z in [-0.90, 0.90]:
				_cylinder(foundation_root, 0.16, 0.07, Vector3(x, 0.035, z), silver)
		for direction in ColonySimulation.NEIGHBORS:
			var at := Vector3(direction.x, 0, direction.y)
			var socket := _box(foundation_root, Vector3(0.3, 0.12, 0.14),
				at * 1.07 + Vector3(0, 0.16, 0), gold)
			socket.rotation.y = PI * 0.5 if direction.x != 0 else 0.0
		return
	_box(foundation_root, Vector3(2.18, 0.13, 2.18), Vector3(0, 0.1, 0), dark)
	for x in [-0.88, 0.88]:
		for z in [-0.88, 0.88]:
			_cylinder(foundation_root, 0.18, 0.08, Vector3(x, 0.04, z), silver)
			_cylinder(foundation_root, 0.075, 0.42, Vector3(x, 0.29, z), silver)
			_box(foundation_root, Vector3(0.14, 0.07, 0.14), Vector3(x, 0.48, z), white)
		_box(foundation_root, Vector3(0.1, 0.16, 1.85), Vector3(x, 0.28, 0), silver)
	for z in [-0.88, 0.88]:
		_box(foundation_root, Vector3(1.85, 0.16, 0.1), Vector3(0, 0.28, z), silver)
		_strut(foundation_root, Vector3(-0.85, 0.2, z), Vector3(0.85, 0.46, z), 0.025, silver)
	# Four matching sockets reach the cell edge without widening the build footprint.
	for direction in ColonySimulation.NEIGHBORS:
		var at := Vector3(direction.x, 0, direction.y)
		var socket := _box(foundation_root, Vector3(0.3, 0.18, 0.16),
			at * 1.07 + Vector3(0, 0.32, 0), gold)
		socket.rotation.y = PI * 0.5 if direction.x != 0 else 0.0


func _pressure_module(kind: String) -> void:
	var hull := _cylinder(body_root, 0.77, 1.6, Vector3(0, 1.2, -0.08), white)
	hull.rotation_degrees.x = 90
	for z in [-0.72, -0.36, 0.0, 0.36, 0.72]:
		var band := _cylinder(body_root, 0.785, 0.055, Vector3(0, 1.2, z - 0.08), silver)
		band.rotation_degrees.x = 90
	for z in [-0.9, 0.75]:
		var cap := _cylinder(body_root, 0.77, 0.16, Vector3(0, 1.2, z), white, 0.82)
		cap.rotation_degrees.x = 90 if z > 0 else -90
	_box(body_root, Vector3(1.05, 0.18, 1.45), Vector3(0, 1.95, -0.08), gold)
	for x in [-0.8, 0.8]:
		_box(body_root, Vector3(0.17, 0.72, 1.15), Vector3(x, 0.9, -0.1), gold)
		for z in [-0.45, 0.35]:
			_strut(body_root, Vector3(x, 0.4, z), Vector3(x * 0.65, 0.8, z), 0.045, silver)
		for z in [-0.5, -0.2, 0.1, 0.4]:
			var frame := _cylinder(body_root, 0.14, 0.05, Vector3(x * 0.94, 1.43, z), silver)
			frame.rotation_degrees.z = 90
			var window := _cylinder(body_root, 0.105, 0.058, frame.position, glass)
			window.rotation_degrees.z = 90
			windows.append(window)
	var hatch := _cylinder(body_root, 0.43, 0.12, Vector3(0, 1.16, 0.91), silver)
	hatch.rotation_degrees.x = 90
	var door := _cylinder(body_root, 0.35, 0.13, Vector3(0, 1.16, 0.94), white)
	door.rotation_degrees.x = 90
	_box(body_root, Vector3(0.11, 0.28, 0.035), Vector3(0.2, 1.16, 1.02), dark)
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var bolt := _cylinder(body_root, 0.025, 0.025,
			Vector3(cos(angle) * 0.39, 1.16 + sin(angle) * 0.39, 0.98), dark)
		bolt.rotation_degrees.x = 90
	for y in [0.36, 0.51, 0.66]:
		_box(body_root, Vector3(0.65, 0.045, 0.14), Vector3(0, y, 1.0), silver)
	_label("SELENE\nHAB-01" if kind == "habitat" else "SELENE\nSCIENCE", Vector3(0, 1.66, 0.91), 28)
	_cylinder(body_root, 0.065, 0.55, Vector3(0.48, 2.18, -0.38), silver)
	mechanism = Node3D.new()
	mechanism.name = "TrackingAntenna"
	mechanism.position = Vector3(0.48, 2.43, -0.38)
	body_root.add_child(mechanism)
	_dish(mechanism, 0.28 if kind == "habitat" else 0.4)
	_equipment_box(Vector3(-0.52, 1.96, -0.4), Vector3(0.35, 0.3, 0.55))
	_lamp_strip(Vector3(0.55, 1.68, 0.86), 3, Vector3(0, -0.09, 0))


func _dish(parent: Node3D, radius: float) -> void:
	var dish := _cylinder(parent, radius, 0.14, Vector3.ZERO, white, 0.35)
	dish.rotation_degrees.x = 65
	_strut(parent, Vector3(-radius * 0.7, 0, 0), Vector3(0, 0.12, 0.3), 0.015, silver)
	_strut(parent, Vector3(radius * 0.7, 0, 0), Vector3(0, 0.12, 0.3), 0.015, silver)
	_box(parent, Vector3(0.07, 0.08, 0.1), Vector3(0, 0.12, 0.3), dark)


func _solar_array() -> void:
	for x in [-0.72, 0.72]:
		_cylinder(body_root, 0.07, 1.35, Vector3(x, 0.98, 0), silver)
		for z in [-0.7, 0.7]:
			_strut(body_root, Vector3(x, 0.45, z), Vector3(x, 1.48, 0), 0.035, silver)
	mechanism = Node3D.new()
	mechanism.name = "SolarTracker"
	mechanism.position = Vector3(0, 1.68, 0)
	mechanism.rotation.x = -0.22
	body_root.add_child(mechanism)
	_strut(mechanism, Vector3(-1.0, -0.06, 0), Vector3(1.0, -0.06, 0), 0.055, silver)
	for x in [-0.55, 0.55]:
		_box(mechanism, Vector3(1.03, 0.065, 2.04), Vector3(x, 0, 0), silver)
		_box(mechanism, Vector3(0.96, 0.016, 1.96), Vector3(x, 0.04, 0), blue)
		for z in [-0.65, 0.0, 0.65]:
			_box(mechanism, Vector3(1.02, 0.018, 0.025), Vector3(x, 0.052, z), silver)
		_box(mechanism, Vector3(0.22, 0.12, 0.3), Vector3(x, -0.11, 0.6), dark)
	_equipment_box(Vector3(0, 0.57, 0.65), Vector3(0.72, 0.4, 0.48))
	_label("POWER / PV-01", Vector3(0, 0.61, 0.9), 24)
	_lamp_strip(Vector3(-0.2, 0.42, 0.91), 4, Vector3(0.13, 0, 0))


func _equipment_box(at: Vector3, size: Vector3) -> void:
	_box(body_root, size, at, white)
	_box(body_root, Vector3(size.x * 0.82, size.y * 0.7, 0.018),
		at + Vector3(0, 0, size.z * 0.5 + 0.01), dark)
	for i in range(5):
		_box(body_root, Vector3(size.x * 0.65, 0.018, 0.02),
			at + Vector3(0, (float(i) - 2.0) * size.y * 0.1, size.z * 0.5 + 0.025), silver)
	for x in [-0.43, 0.43]:
		for y in [-0.4, 0.4]:
			var bolt := _cylinder(body_root, 0.018, 0.02,
				at + Vector3(size.x * x, size.y * y, size.z * 0.5 + 0.015), silver)
			bolt.rotation_degrees.x = 90


func _service_panel(at: Vector3, size: Vector2) -> void:
	_box(body_root, Vector3(size.x, size.y, 0.035), at, silver)
	_box(body_root, Vector3(size.x - 0.06, size.y - 0.06, 0.04), at + Vector3(0, 0, 0.01), white)
	for y in [-size.y * 0.32, size.y * 0.32]:
		_box(body_root, Vector3(0.065, 0.1, 0.045), at + Vector3(-size.x * 0.42, y, 0.035), silver)
	_box(body_root, Vector3(0.035, size.y * 0.25, 0.05), at + Vector3(size.x * 0.32, 0, 0.04), dark)


func _valve(at: Vector3) -> void:
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.065
	wheel.outer_radius = 0.095
	wheel.rings = 16
	wheel.ring_segments = 8
	var instance := _mesh(body_root, wheel, at, accent)
	instance.rotation_degrees.x = 90
	_strut(body_root, at + Vector3(-0.075, 0, 0), at + Vector3(0.075, 0, 0), 0.014, silver)
	_strut(body_root, at + Vector3(0, -0.075, 0), at + Vector3(0, 0.075, 0), 0.014, silver)


func _tank(at: Vector3, radius: float, height: float) -> void:
	_cylinder(body_root, radius, height, at, white)
	for y in [-height * 0.38, height * 0.38]:
		_cylinder(body_root, radius * 1.025, 0.055, at + Vector3(0, y, 0), silver)
	var cap := SphereMesh.new()
	cap.radius = radius
	cap.height = radius * 2.0
	var top := _mesh(body_root, cap, at + Vector3(0, height * 0.5, 0), white)
	top.scale.y = 0.45
	_cylinder(body_root, 0.06, 0.14, at + Vector3(0, height * 0.5 + radius * 0.45, 0), silver)
	_box(body_root, Vector3(radius * 1.2, 0.1, 0.018), at + Vector3(0, 0.15, radius), accent)


func _processing_module(kind: String) -> void:
	_box(body_root, Vector3(0.93, 1.22, 1.38), Vector3(0.43, 1.08, -0.15), gold)
	_box(body_root, Vector3(1.02, 0.1, 1.48), Vector3(0.43, 1.75, -0.15), white)
	_equipment_box(Vector3(0.43, 1.08, 0.62), Vector3(0.82, 0.65, 0.12))
	for z in [-0.52, 0.32]:
		_tank(Vector3(-0.62, 1.08, z), 0.29, 1.12)
		_strut(body_root, Vector3(-0.62, 1.8, z), Vector3(0.32, 1.8, z), 0.035, silver)
		_strut(body_root, Vector3(-0.62, 0.52, z), Vector3(0.3, 0.52, z), 0.035, accent)
		for x in [-0.92, -0.32]:
			_strut(body_root, Vector3(x, 0.4, z), Vector3(x, 1.45, z), 0.026, silver)
		_valve(Vector3(-0.62, 0.59, z + 0.31))
	for x in [0.15, 0.71]:
		_service_panel(Vector3(x, 1.38, 0.57), Vector2(0.44, 0.32))
	_strut(body_root, Vector3(-0.32, 0.55, 0.72), Vector3(0.84, 0.55, 0.72), 0.028, silver)
	_strut(body_root, Vector3(0.84, 0.55, 0.72), Vector3(0.84, 1.56, 0.72), 0.028, silver)
	_label("H2O / ISRU" if kind == "ice" else "O2 / ECLSS", Vector3(0.43, 1.6, 0.59), 23)
	_lamp_strip(Vector3(0.17, 0.66, 0.71), 5, Vector3(0.12, 0, 0))
	if kind == "ice":
		for x in [0.12, 0.75]:
			_strut(body_root, Vector3(x, 0.4, 0.88), Vector3(0.43, 2.55, 0.88), 0.05, silver)
		for y in [1.3, 1.85, 2.4]:
			_box(body_root, Vector3(0.65, 0.07, 0.22), Vector3(0.43, y, 0.88), accent)
		mechanism = Node3D.new()
		mechanism.name = "ExtractionDrill"
		mechanism.position = Vector3(0.43, 1.18, 0.88)
		body_root.add_child(mechanism)
		_cylinder(mechanism, 0.09, 1.8, Vector3.ZERO, dark)
		for i in range(14):
			var tooth := _box(mechanism, Vector3(0.28, 0.04, 0.12),
				Vector3(0, -0.8 + float(i) * 0.12, 0), silver)
			tooth.rotation.y = float(i) * 0.7
		_equipment_box(Vector3(0.43, 2.52, 0.88), Vector3(0.42, 0.27, 0.4))
	else:
		_box(body_root, Vector3(0.75, 0.09, 0.65), Vector3(0.43, 1.89, -0.1), dark)
		for x in [0.14, 0.29, 0.44, 0.59, 0.74]:
			_box(body_root, Vector3(0.045, 0.34, 0.62), Vector3(x, 2.08, -0.1), silver)
		mechanism = Node3D.new()
		mechanism.name = "RecirculationPump"
		mechanism.position = Vector3(0.43, 1.06, 0.77)
		body_root.add_child(mechanism)
		for x in [-0.24, 0.24]:
			_cylinder(mechanism, 0.055, 0.28, Vector3(x, 0, 0), silver)
		_box(mechanism, Vector3(0.58, 0.08, 0.12), Vector3(0, 0.16, 0), accent)


func _reactor() -> void:
	_cylinder(body_root, 0.53, 1.45, Vector3(0, 1.17, -0.12), gold)
	for y in [0.55, 1.18, 1.86]:
		_cylinder(body_root, 0.57, 0.09, Vector3(0, y, -0.12), silver)
	_cylinder(body_root, 0.53, 0.25, Vector3(0, 2.01, -0.12), white, 0.6)
	for x in [-0.86, 0.86]:
		_box(body_root, Vector3(0.09, 1.6, 1.65), Vector3(x, 1.24, -0.03), dark)
		for z in [-0.8, -0.6, -0.4, -0.2, 0.0, 0.2, 0.4, 0.6, 0.8]:
			_box(body_root, Vector3(0.13, 1.5, 0.035), Vector3(x, 1.24, z - 0.03), silver)
		for y in [0.57, 1.96]:
			_strut(body_root, Vector3(0, y, -0.12), Vector3(x, y, -0.12), 0.035, silver)
	_equipment_box(Vector3(0, 0.64, 0.77), Vector3(0.95, 0.4, 0.3))
	_label("FISSION / KEEP CLEAR", Vector3(0, 0.7, 0.94), 19)
	_lamp_strip(Vector3(-0.3, 0.5, 0.94), 6, Vector3(0.12, 0, 0))


func _refinery() -> void:
	_box(body_root, Vector3(1.2, 0.95, 1.25), Vector3(-0.24, 0.98, -0.12), gold)
	_equipment_box(Vector3(-0.24, 0.95, 0.55), Vector3(1.1, 0.65, 0.12))
	_cylinder(body_root, 0.43, 0.5, Vector3(-0.24, 1.72, -0.12), silver, 1.3)
	_cylinder(body_root, 0.39, 0.04, Vector3(-0.24, 1.98, -0.12), dark)
	for z in [-0.85, 0.85]:
		_strut(body_root, Vector3(0.72, 0.4, z), Vector3(0.72, 0.83, z), 0.045, silver)
	_box(body_root, Vector3(0.48, 0.08, 1.9), Vector3(0.72, 0.7, 0), dark)
	for x in [0.46, 0.98]:
		_box(body_root, Vector3(0.04, 0.16, 1.95), Vector3(x, 0.77, 0), silver)
	for z in [-0.8, -0.4, 0, 0.4, 0.8]:
		var roller := _cylinder(body_root, 0.055, 0.46, Vector3(0.72, 0.76, z), silver)
		roller.rotation_degrees.z = 90
	mechanism = Node3D.new()
	mechanism.name = "ConveyorDrive"
	mechanism.position = Vector3(0.72, 0.76, 0.9)
	body_root.add_child(mechanism)
	var drum := _cylinder(mechanism, 0.12, 0.48, Vector3.ZERO, accent)
	drum.rotation_degrees.z = 90
	_box(mechanism, Vector3(0.49, 0.04, 0.22), Vector3.ZERO, silver)
	_label("REGOLITH / ISRU", Vector3(-0.24, 1.32, 0.53), 24)
	_lamp_strip(Vector3(-0.54, 0.64, 0.64), 5, Vector3(0.14, 0, 0))


func _landing_pad() -> void:
	# Sintered regolith touchdown deck (top surface sits at y = 0.22).
	_box(body_root, Vector3(1.94, 0.08, 1.94), Vector3(0, 0.18, 0), dark)
	# Perimeter blast deflector berms stay strictly inside ±1.12.
	for z in [-0.98, 0.98]:
		var berm := _box(body_root, Vector3(1.86, 0.13, 0.14), Vector3(0, 0.21, z), silver)
		berm.rotation_degrees.x = 18.0 if z < 0.0 else -18.0
	for x in [-0.98, 0.98]:
		var berm := _box(body_root, Vector3(0.14, 0.13, 1.86), Vector3(x, 0.21, 0), silver)
		berm.rotation_degrees.z = -18.0 if x < 0.0 else 18.0
	# High-contrast landing target ring, corner brackets and central H marking.
	for x in [-0.30, 0.30]:
		_box(body_root, Vector3(0.08, 0.012, 0.68), Vector3(x, 0.226, 0), white)
	_box(body_root, Vector3(0.62, 0.012, 0.09), Vector3(0, 0.226, 0), accent)
	for cx in [-0.66, 0.66]:
		for cz in [-0.66, 0.66]:
			_box(body_root, Vector3(0.24, 0.012, 0.06), Vector3(cx, 0.226, cz), accent)
			_box(body_root, Vector3(0.06, 0.012, 0.24), Vector3(cx, 0.226, cz), accent)
	# Perimeter approach edge lights integrated with telemetry lamps.
	for lx in [-0.92, 0.92]:
		for lz in [-0.92, 0.92]:
			_cylinder(body_root, 0.055, 0.08, Vector3(lx, 0.27, lz), dark)
			lamps.append(_box(body_root, Vector3(0.065, 0.045, 0.065),
				Vector3(lx, 0.33, lz), lit))
	# Back-left approach beacon mast (stays clear of central touchdown zone, gives >=1.7 silhouette).
	var mast_at := Vector3(-0.82, 0.0, -0.82)
	_box(body_root, Vector3(0.32, 0.28, 0.30), mast_at + Vector3(0, 0.34, 0), gold)
	_cylinder(body_root, 0.05, 1.50, mast_at + Vector3(0, 1.08, 0), silver)
	_strut(body_root, mast_at + Vector3(0.14, 0.30, 0.14), mast_at + Vector3(0, 1.35, 0), 0.022, silver)
	_strut(body_root, mast_at + Vector3(-0.14, 0.30, 0.14), mast_at + Vector3(0, 1.15, 0), 0.022, silver)
	_box(body_root, Vector3(0.18, 0.12, 0.16), mast_at + Vector3(0, 1.62, 0), white)
	mechanism = Node3D.new()
	mechanism.name = "ApproachBeacon"
	mechanism.position = mast_at + Vector3(0, 1.84, 0)
	body_root.add_child(mechanism)
	_dish(mechanism, 0.22)
	lamps.append(_box(mechanism, Vector3(0.07, 0.07, 0.07), Vector3(0, 0.16, 0), lit))
	# Front-right cargo transfer cradle and pad telemetry signage on +Z.
	_box(body_root, Vector3(0.34, 0.05, 0.30), Vector3(0.60, 0.24, 0.46), silver)
	_box(body_root, Vector3(0.58, 0.14, 0.05), Vector3(0.0, 0.33, 0.96), white)
	_label("SELENE / PAD-01", Vector3(0.0, 0.34, 1.00), 19)


func _utility_link() -> void:
	for direction in ColonySimulation.NEIGHBORS:
		var end := Vector3(direction.x, 0, direction.y) * 1.12
		for offset in [-0.13, 0.13]:
			var side: Vector3 = Vector3(-direction.y, 0, direction.x) * offset
			_strut(body_root, side + Vector3(0, 0.23, 0), end + side + Vector3(0, 0.23, 0),
				0.045, silver if offset < 0 else accent)
	_box(body_root, Vector3(0.48, 0.25, 0.48), Vector3(0, 0.3, 0), gold)
	_lamp_strip(Vector3(-0.12, 0.45, 0.12), 3, Vector3(0.12, 0, 0))


func _lamp_strip(at: Vector3, count: int, step: Vector3) -> void:
	for i in range(count):
		lamps.append(_box(body_root, Vector3(0.045, 0.035, 0.025), at + step * float(i), lit))
