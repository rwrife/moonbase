class_name SupplyLander
extends Node3D

## Original fictional SELENE cargo lander for recurring supply pad visits.
## Purely cosmetic: pose, visibility, cargo offload and engine glow are derived
## deterministically from the authoritative delivery record in ColonySimulation.

const SURFACE_SHADER := preload("res://shaders/module_surface.gdshader")
const DECK_Y := 0.22

var craft: Node3D
var cargo_pod: Node3D
var thruster_glow: MeshInstance3D
var landing_light: OmniLight3D
var nav_lamps: Array[MeshInstance3D] = []
var current_phase := "waiting"
var current_progress := 0.0


func _init() -> void:
	_build()
	visible = false


func _build() -> void:
	var silver := _material(Color(0.57, 0.61, 0.65), 0.8, 0.32)
	var white := _material(Color(0.86, 0.87, 0.84), 0.15, 0.6)
	var dark := _material(Color(0.055, 0.067, 0.08), 0.5, 0.75)
	var accent := _material(Color(0.86, 0.68, 0.28), 0.25, 0.5)
	var gold := ShaderMaterial.new()
	gold.shader = SURFACE_SHADER
	gold.set_shader_parameter("base_color", Color(0.72, 0.52, 0.22))
	var lamp_mat := _material(Color(0.35, 0.88, 0.72), 0.0, 0.35)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(0.18, 0.75, 0.52)
	lamp_mat.emission_energy_multiplier = 2.0

	craft = Node3D.new()
	craft.name = "LanderCraft"
	add_child(craft)

	# Descent stage wrapped in quilted MLI thermal foil.
	_cylinder(craft, 0.44, 0.30, Vector3(0, 0.54, 0), gold)
	_cylinder(craft, 0.46, 0.05, Vector3(0, 0.40, 0), dark)
	_cylinder(craft, 0.46, 0.05, Vector3(0, 0.68, 0), silver)

	# Four splayed landing legs with circular footpads resting cleanly at y = 0.
	for i in range(4):
		var angle := PI * 0.25 + float(i) * PI * 0.5
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var foot := dir * 0.60 + Vector3(0, 0.025, 0)
		_cylinder(craft, 0.11, 0.05, foot, silver)
		_strut(craft, dir * 0.41 + Vector3(0, 0.62, 0), foot + Vector3(0, 0.02, 0), 0.032, silver)
		_strut(craft, dir * 0.40 + Vector3(0, 0.40, 0), dir * 0.50 + Vector3(0, 0.24, 0), 0.022, dark)

	# Main descent engine bell (vacuum-rated nozzle, no atmospheric smoke).
	_cylinder(craft, 0.15, 0.18, Vector3(0, 0.31, 0), dark, 0.55)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.72, 0.86, 1.0, 0.45)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.55, 0.78, 1.0)
	glow_mat.emission_energy_multiplier = 2.6
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cone := CylinderMesh.new()
	cone.top_radius = 0.11
	cone.bottom_radius = 0.02
	cone.height = 0.42
	cone.radial_segments = 16
	thruster_glow = _mesh(craft, cone, Vector3(0, 0.02, 0), glow_mat)
	thruster_glow.name = "VacuumNozzleGlow"
	thruster_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Pressurized upper cargo module + SELENE markings.
	_cylinder(craft, 0.35, 0.46, Vector3(0, 0.94, 0), white)
	for y in [0.76, 1.12]:
		_cylinder(craft, 0.365, 0.04, Vector3(0, y, 0), silver)
	_cylinder(craft, 0.36, 0.06, Vector3(0, 0.94, 0), accent)
	_cylinder(craft, 0.35, 0.12, Vector3(0, 1.23, 0), white, 0.62)
	_cylinder(craft, 0.14, 0.08, Vector3(0, 1.32, 0), silver)

	# Four attitude RCS thruster quads.
	for i in range(4):
		var angle := float(i) * PI * 0.5
		var pos := Vector3(cos(angle) * 0.38, 1.05, sin(angle) * 0.38)
		_box(craft, Vector3(0.08, 0.08, 0.08), pos, dark)

	# Front marking and navigation beacon lamps.
	var label := Label3D.new()
	label.text = "SELENE\nCARGO"
	label.font_size = 22
	label.pixel_size = 0.0035
	label.position = Vector3(0, 0.96, 0.37)
	label.modulate = Color(0.12, 0.18, 0.24)
	label.outline_size = 0
	craft.add_child(label)

	for side in [-1.0, 1.0]:
		nav_lamps.append(_box(craft, Vector3(0.05, 0.04, 0.05), Vector3(side * 0.45, 0.69, 0.0), lamp_mat))

	landing_light = OmniLight3D.new()
	landing_light.name = "LandingLight"
	landing_light.position = Vector3(0, 0.22, 0.25)
	landing_light.light_color = Color(1.0, 0.92, 0.78)
	landing_light.light_energy = 0.85
	landing_light.omni_range = 3.2
	craft.add_child(landing_light)

	# Standard cargo container visibly lowered onto the pad deck during offload.
	cargo_pod = Node3D.new()
	cargo_pod.name = "CargoPod"
	cargo_pod.position = Vector3(0.32, 0.32, 0.24)
	craft.add_child(cargo_pod)
	_box(cargo_pod, Vector3(0.28, 0.20, 0.24), Vector3.ZERO, white)
	_box(cargo_pod, Vector3(0.29, 0.05, 0.25), Vector3(0, 0.03, 0), accent)
	_box(cargo_pod, Vector3(0.24, 0.02, 0.20), Vector3(0, 0.11, 0), gold)


func apply_delivery(delivery: Dictionary) -> void:
	if delivery.is_empty():
		current_phase = "waiting"
		current_progress = 0.0
		visible = false
		return
	var phase := str(delivery.get("phase", "waiting"))
	var p := clampf(float(delivery.get("phase_progress", 0.0)), 0.0, 1.0)
	current_phase = phase
	current_progress = p
	match phase:
		"waiting":
			visible = false
			craft.position = Vector3(0, 14.0, 0)
			craft.rotation = Vector3.ZERO
			thruster_glow.visible = false
			landing_light.visible = false
			cargo_pod.visible = false
		"approaching":
			visible = true
			var ease_out := 1.0 - pow(1.0 - p, 2.0)
			craft.position = Vector3(
				lerpf(1.8, 0.0, ease_out),
				lerpf(5.8, 2.8, ease_out),
				lerpf(-1.2, 0.0, ease_out)
			)
			var tilt := lerpf(0.20, 0.04, ease_out)
			craft.rotation = Vector3(-tilt * 0.6, 0.0, tilt)
			thruster_glow.visible = true
			thruster_glow.scale = Vector3(0.85, 0.8, 0.85)
			landing_light.visible = true
			cargo_pod.visible = true
			cargo_pod.position = Vector3(0.32, 0.34, 0.24)
		"descending":
			visible = true
			var ease_out := 1.0 - pow(1.0 - p, 2.2)
			craft.position = Vector3(0.0, lerpf(2.8, DECK_Y, ease_out), 0.0)
			craft.rotation = Vector3(0.0, 0.0, lerpf(0.04, 0.0, ease_out))
			thruster_glow.visible = true
			var thrust := lerpf(1.0, 0.35, ease_out)
			thruster_glow.scale = Vector3(thrust, thrust, thrust)
			landing_light.visible = true
			cargo_pod.visible = true
			cargo_pod.position = Vector3(0.32, 0.34, 0.24)
		"delivering":
			visible = true
			craft.position = Vector3(0.0, DECK_Y, 0.0)
			craft.rotation = Vector3.ZERO
			thruster_glow.visible = false
			landing_light.visible = true
			cargo_pod.visible = true
			var drop := clampf(p * 1.4, 0.0, 1.0)
			cargo_pod.position = Vector3(
				lerpf(0.32, 0.56, drop),
				lerpf(0.34, 0.11, drop),
				lerpf(0.24, 0.44, drop)
			)
		"departing":
			visible = true
			var ease_in := p * p
			craft.position = Vector3(
				lerpf(0.0, -2.4, ease_in),
				lerpf(DECK_Y, 8.8, ease_in),
				lerpf(0.0, -2.0, ease_in)
			)
			var pitch := lerpf(0.0, 0.24, ease_in)
			craft.rotation = Vector3(-pitch * 0.55, 0.0, pitch)
			thruster_glow.visible = true
			thruster_glow.scale = Vector3(1.05, 1.15, 1.05)
			landing_light.visible = p < 0.7
			cargo_pod.visible = false
		_:
			visible = false


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
	mesh.radial_segments = 24
	return _mesh(parent, mesh, at, material)


func _strut(parent: Node3D, start: Vector3, end: Vector3, radius: float,
		material: Material) -> MeshInstance3D:
	var rod := _cylinder(parent, radius, start.distance_to(end), (start + end) * 0.5, material)
	rod.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return rod
