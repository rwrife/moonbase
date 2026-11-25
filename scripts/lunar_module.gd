class_name LunarModule
extends Node3D

const SURFACE_SHADER := preload("res://shaders/module_surface.gdshader")

var active := false
var operating_time := 0.0
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
var glass: StandardMaterial3D
var status_material: StandardMaterial3D


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
	glass = _material(Color(0.035, 0.07, 0.1), 0.6, 0.2)
	glass.emission_enabled = true
	status_material = _material(Color(0.8, 0.19, 0.07))
	status_material.emission_enabled = true
	status_material.emission = Color(0.8, 0.09, 0.025)
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
	status = _box(self, Vector3(0.24, 0.045, 0.1), Vector3(0, 0.46, 1.06),
		status_material)
	status.name = "OperatingStatus"
	if kind != "link":
		var fixture_at := Vector3(0.78, 1.5, 0.85)
		_box(self, Vector3(0.13, 0.08, 0.12), fixture_at, dark)
		_box(self, Vector3(0.09, 0.025, 0.08),
			fixture_at + Vector3(0, -0.045, 0.02), glass)
		work_light = OmniLight3D.new()
		work_light.name = "ServiceLight"
		work_light.position = fixture_at + Vector3(0, -0.12, 0.12)
		work_light.light_color = Color(1.0, 0.83, 0.59)
		work_light.light_energy = 0.45
		work_light.omni_range = 2.4
		add_child(work_light)
	set_active(false)


func set_active(value: bool) -> void:
	var was_active := active
	active = value
	status_material.albedo_color = Color(0.19, 0.8, 0.5) if active else Color(0.8, 0.19, 0.07)
	status_material.emission = Color(0.08, 0.55, 0.28) if active else Color(0.6, 0.06, 0.015)
	status_material.emission_energy_multiplier = 1.4 if active else 0.6
	glass.emission = Color(0.8, 0.48, 0.18) if active else Color.BLACK
	glass.emission_energy_multiplier = 0.65 if active else 0.0
	if work_light != null:
		work_light.visible = active
	if not active or not was_active:
		for lamp in lamps:
			lamp.material_override = lit if active else unlit


func advance(delta: float) -> void:
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
	for i in range(lamps.size()):
		var on := fposmod(operating_time * 2.0 - float(i) * 0.35, 2.0) < 1.0
		lamps[i].material_override = lit if on else unlit


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
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.position = at
	label.modulate = Color(0.12, 0.18, 0.24)
	label.outline_size = 0
	add_child(label)


func _foundation(kind: String) -> void:
	if kind == "link":
		return
	_box(self, Vector3(2.18, 0.13, 2.18), Vector3(0, 0.1, 0), dark)
	for x in [-0.88, 0.88]:
		for z in [-0.88, 0.88]:
			_cylinder(self, 0.18, 0.08, Vector3(x, 0.04, z), silver)
			_cylinder(self, 0.075, 0.42, Vector3(x, 0.29, z), silver)
			_box(self, Vector3(0.14, 0.07, 0.14), Vector3(x, 0.48, z), white)
		_box(self, Vector3(0.1, 0.16, 1.85), Vector3(x, 0.28, 0), silver)
	for z in [-0.88, 0.88]:
		_box(self, Vector3(1.85, 0.16, 0.1), Vector3(0, 0.28, z), silver)
		_strut(self, Vector3(-0.85, 0.2, z), Vector3(0.85, 0.46, z), 0.025, silver)
	# Four matching sockets reach the cell edge without widening the build footprint.
	for direction in ColonySimulation.NEIGHBORS:
		var at := Vector3(direction.x, 0, direction.y)
		var socket := _box(self, Vector3(0.3, 0.18, 0.16), at * 1.07 + Vector3(0, 0.32, 0), gold)
		socket.rotation.y = PI * 0.5 if direction.x != 0 else 0.0


func _pressure_module(kind: String) -> void:
	var hull := _cylinder(self, 0.77, 1.6, Vector3(0, 1.2, -0.08), white)
	hull.rotation_degrees.x = 90
	for z in [-0.72, -0.36, 0.0, 0.36, 0.72]:
		var band := _cylinder(self, 0.785, 0.055, Vector3(0, 1.2, z - 0.08), silver)
		band.rotation_degrees.x = 90
	for z in [-0.9, 0.75]:
		var cap := _cylinder(self, 0.77, 0.16, Vector3(0, 1.2, z), white, 0.82)
		cap.rotation_degrees.x = 90 if z > 0 else -90
	_box(self, Vector3(1.05, 0.18, 1.45), Vector3(0, 1.95, -0.08), gold)
	for x in [-0.8, 0.8]:
		_box(self, Vector3(0.17, 0.72, 1.15), Vector3(x, 0.9, -0.1), gold)
		for z in [-0.45, 0.35]:
			_strut(self, Vector3(x, 0.4, z), Vector3(x * 0.65, 0.8, z), 0.045, silver)
		for z in [-0.5, -0.2, 0.1, 0.4]:
			var frame := _cylinder(self, 0.14, 0.05, Vector3(x * 0.94, 1.43, z), silver)
			frame.rotation_degrees.z = 90
			var window := _cylinder(self, 0.105, 0.058, frame.position, glass)
			window.rotation_degrees.z = 90
			windows.append(window)
	var hatch := _cylinder(self, 0.43, 0.12, Vector3(0, 1.16, 0.91), silver)
	hatch.rotation_degrees.x = 90
	var door := _cylinder(self, 0.35, 0.13, Vector3(0, 1.16, 0.94), white)
	door.rotation_degrees.x = 90
	_box(self, Vector3(0.11, 0.28, 0.035), Vector3(0.2, 1.16, 1.02), dark)
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var bolt := _cylinder(self, 0.025, 0.025,
			Vector3(cos(angle) * 0.39, 1.16 + sin(angle) * 0.39, 0.98), dark)
		bolt.rotation_degrees.x = 90
	for y in [0.36, 0.51, 0.66]:
		_box(self, Vector3(0.65, 0.045, 0.14), Vector3(0, y, 1.0), silver)
	_label("SELENE\nHAB-01" if kind == "habitat" else "SELENE\nSCIENCE", Vector3(0, 1.66, 0.91), 28)
	_cylinder(self, 0.065, 0.55, Vector3(0.48, 2.18, -0.38), silver)
	mechanism = Node3D.new()
	mechanism.name = "TrackingAntenna"
	mechanism.position = Vector3(0.48, 2.43, -0.38)
	add_child(mechanism)
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
		_cylinder(self, 0.07, 1.35, Vector3(x, 0.98, 0), silver)
		for z in [-0.7, 0.7]:
			_strut(self, Vector3(x, 0.45, z), Vector3(x, 1.48, 0), 0.035, silver)
	mechanism = Node3D.new()
	mechanism.name = "SolarTracker"
	mechanism.position = Vector3(0, 1.68, 0)
	mechanism.rotation.x = -0.22
	add_child(mechanism)
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
	_box(self, size, at, white)
	_box(self, Vector3(size.x * 0.82, size.y * 0.7, 0.018),
		at + Vector3(0, 0, size.z * 0.5 + 0.01), dark)
	for i in range(5):
		_box(self, Vector3(size.x * 0.65, 0.018, 0.02),
			at + Vector3(0, (float(i) - 2.0) * size.y * 0.1, size.z * 0.5 + 0.025), silver)
	for x in [-0.43, 0.43]:
		for y in [-0.4, 0.4]:
			var bolt := _cylinder(self, 0.018, 0.02,
				at + Vector3(size.x * x, size.y * y, size.z * 0.5 + 0.015), silver)
			bolt.rotation_degrees.x = 90


func _service_panel(at: Vector3, size: Vector2) -> void:
	_box(self, Vector3(size.x, size.y, 0.035), at, silver)
	_box(self, Vector3(size.x - 0.06, size.y - 0.06, 0.04), at + Vector3(0, 0, 0.01), white)
	for y in [-size.y * 0.32, size.y * 0.32]:
		_box(self, Vector3(0.065, 0.1, 0.045), at + Vector3(-size.x * 0.42, y, 0.035), silver)
	_box(self, Vector3(0.035, size.y * 0.25, 0.05), at + Vector3(size.x * 0.32, 0, 0.04), dark)


func _valve(at: Vector3) -> void:
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.065
	wheel.outer_radius = 0.095
	wheel.rings = 16
	wheel.ring_segments = 8
	var instance := _mesh(self, wheel, at, accent)
	instance.rotation_degrees.x = 90
	_strut(self, at + Vector3(-0.075, 0, 0), at + Vector3(0.075, 0, 0), 0.014, silver)
	_strut(self, at + Vector3(0, -0.075, 0), at + Vector3(0, 0.075, 0), 0.014, silver)


func _tank(at: Vector3, radius: float, height: float) -> void:
	_cylinder(self, radius, height, at, white)
	for y in [-height * 0.38, height * 0.38]:
		_cylinder(self, radius * 1.025, 0.055, at + Vector3(0, y, 0), silver)
	var cap := SphereMesh.new()
	cap.radius = radius
	cap.height = radius * 2.0
	var top := _mesh(self, cap, at + Vector3(0, height * 0.5, 0), white)
	top.scale.y = 0.45
	_cylinder(self, 0.06, 0.14, at + Vector3(0, height * 0.5 + radius * 0.45, 0), silver)
	_box(self, Vector3(radius * 1.2, 0.1, 0.018), at + Vector3(0, 0.15, radius), accent)


func _processing_module(kind: String) -> void:
	_box(self, Vector3(0.93, 1.22, 1.38), Vector3(0.43, 1.08, -0.15), gold)
	_box(self, Vector3(1.02, 0.1, 1.48), Vector3(0.43, 1.75, -0.15), white)
	_equipment_box(Vector3(0.43, 1.08, 0.62), Vector3(0.82, 0.65, 0.12))
	for z in [-0.52, 0.32]:
		_tank(Vector3(-0.62, 1.08, z), 0.29, 1.12)
		_strut(self, Vector3(-0.62, 1.8, z), Vector3(0.32, 1.8, z), 0.035, silver)
		_strut(self, Vector3(-0.62, 0.52, z), Vector3(0.3, 0.52, z), 0.035, accent)
		for x in [-0.92, -0.32]:
			_strut(self, Vector3(x, 0.4, z), Vector3(x, 1.45, z), 0.026, silver)
		_valve(Vector3(-0.62, 0.59, z + 0.31))
	for x in [0.15, 0.71]:
		_service_panel(Vector3(x, 1.38, 0.57), Vector2(0.44, 0.32))
	_strut(self, Vector3(-0.32, 0.55, 0.72), Vector3(0.84, 0.55, 0.72), 0.028, silver)
	_strut(self, Vector3(0.84, 0.55, 0.72), Vector3(0.84, 1.56, 0.72), 0.028, silver)
	_label("H2O / ISRU" if kind == "ice" else "O2 / ECLSS", Vector3(0.43, 1.6, 0.59), 23)
	_lamp_strip(Vector3(0.17, 0.66, 0.71), 5, Vector3(0.12, 0, 0))
	if kind == "ice":
		for x in [0.12, 0.75]:
			_strut(self, Vector3(x, 0.4, 0.88), Vector3(0.43, 2.55, 0.88), 0.05, silver)
		for y in [1.3, 1.85, 2.4]:
			_box(self, Vector3(0.65, 0.07, 0.22), Vector3(0.43, y, 0.88), accent)
		mechanism = Node3D.new()
		mechanism.name = "ExtractionDrill"
		mechanism.position = Vector3(0.43, 1.18, 0.88)
		add_child(mechanism)
		_cylinder(mechanism, 0.09, 1.8, Vector3.ZERO, dark)
		for i in range(14):
			var tooth := _box(mechanism, Vector3(0.28, 0.04, 0.12),
				Vector3(0, -0.8 + float(i) * 0.12, 0), silver)
			tooth.rotation.y = float(i) * 0.7
		_equipment_box(Vector3(0.43, 2.52, 0.88), Vector3(0.42, 0.27, 0.4))
	else:
		_box(self, Vector3(0.75, 0.09, 0.65), Vector3(0.43, 1.89, -0.1), dark)
		for x in [0.14, 0.29, 0.44, 0.59, 0.74]:
			_box(self, Vector3(0.045, 0.34, 0.62), Vector3(x, 2.08, -0.1), silver)
		mechanism = Node3D.new()
		mechanism.name = "RecirculationPump"
		mechanism.position = Vector3(0.43, 1.06, 0.77)
		add_child(mechanism)
		for x in [-0.24, 0.24]:
			_cylinder(mechanism, 0.055, 0.28, Vector3(x, 0, 0), silver)
		_box(mechanism, Vector3(0.58, 0.08, 0.12), Vector3(0, 0.16, 0), accent)


func _reactor() -> void:
	_cylinder(self, 0.53, 1.45, Vector3(0, 1.17, -0.12), gold)
	for y in [0.55, 1.18, 1.86]:
		_cylinder(self, 0.57, 0.09, Vector3(0, y, -0.12), silver)
	_cylinder(self, 0.53, 0.25, Vector3(0, 2.01, -0.12), white, 0.6)
	for x in [-0.86, 0.86]:
		_box(self, Vector3(0.09, 1.6, 1.65), Vector3(x, 1.24, -0.03), dark)
		for z in [-0.8, -0.6, -0.4, -0.2, 0.0, 0.2, 0.4, 0.6, 0.8]:
			_box(self, Vector3(0.13, 1.5, 0.035), Vector3(x, 1.24, z - 0.03), silver)
		for y in [0.57, 1.96]:
			_strut(self, Vector3(0, y, -0.12), Vector3(x, y, -0.12), 0.035, silver)
	_equipment_box(Vector3(0, 0.64, 0.77), Vector3(0.95, 0.4, 0.3))
	_label("FISSION / KEEP CLEAR", Vector3(0, 0.7, 0.94), 19)
	_lamp_strip(Vector3(-0.3, 0.5, 0.94), 6, Vector3(0.12, 0, 0))


func _refinery() -> void:
	_box(self, Vector3(1.2, 0.95, 1.25), Vector3(-0.24, 0.98, -0.12), gold)
	_equipment_box(Vector3(-0.24, 0.95, 0.55), Vector3(1.1, 0.65, 0.12))
	_cylinder(self, 0.43, 0.5, Vector3(-0.24, 1.72, -0.12), silver, 1.3)
	_cylinder(self, 0.39, 0.04, Vector3(-0.24, 1.98, -0.12), dark)
	for z in [-0.85, 0.85]:
		_strut(self, Vector3(0.72, 0.4, z), Vector3(0.72, 0.83, z), 0.045, silver)
	_box(self, Vector3(0.48, 0.08, 1.9), Vector3(0.72, 0.7, 0), dark)
	for x in [0.46, 0.98]:
		_box(self, Vector3(0.04, 0.16, 1.95), Vector3(x, 0.77, 0), silver)
	for z in [-0.8, -0.4, 0, 0.4, 0.8]:
		var roller := _cylinder(self, 0.055, 0.46, Vector3(0.72, 0.76, z), silver)
		roller.rotation_degrees.z = 90
	mechanism = Node3D.new()
	mechanism.name = "ConveyorDrive"
	mechanism.position = Vector3(0.72, 0.76, 0.9)
	add_child(mechanism)
	var drum := _cylinder(mechanism, 0.12, 0.48, Vector3.ZERO, accent)
	drum.rotation_degrees.z = 90
	_box(mechanism, Vector3(0.49, 0.04, 0.22), Vector3.ZERO, silver)
	_label("REGOLITH / ISRU", Vector3(-0.24, 1.32, 0.53), 24)
	_lamp_strip(Vector3(-0.54, 0.64, 0.64), 5, Vector3(0.14, 0, 0))


func _utility_link() -> void:
	for direction in ColonySimulation.NEIGHBORS:
		var end := Vector3(direction.x, 0, direction.y) * 1.12
		for offset in [-0.13, 0.13]:
			var side: Vector3 = Vector3(-direction.y, 0, direction.x) * offset
			_strut(self, side + Vector3(0, 0.23, 0), end + side + Vector3(0, 0.23, 0),
				0.045, silver if offset < 0 else accent)
		for fraction in [0.35, 0.7, 0.95]:
			_box(self, Vector3(0.32, 0.05, 0.32), end * fraction + Vector3(0, 0.15, 0), dark)
	_box(self, Vector3(0.48, 0.25, 0.48), Vector3(0, 0.3, 0), gold)
	_lamp_strip(Vector3(-0.12, 0.45, 0.12), 3, Vector3(0.12, 0, 0))


func _lamp_strip(at: Vector3, count: int, step: Vector3) -> void:
	for i in range(count):
		lamps.append(_box(self, Vector3(0.045, 0.035, 0.025), at + step * float(i), lit))
