class_name LunarSite
extends Node3D

const CELL_SIZE := 2.3

var models: Dictionary = {}
var indicators: Dictionary = {}
var preview: MeshInstance3D
var sun: DirectionalLight3D
var good_material: StandardMaterial3D
var bad_material: StandardMaterial3D
var neutral_material: StandardMaterial3D


func _ready() -> void:
	good_material = _material(Color(0.3, 0.95, 0.72), true)
	bad_material = _material(Color(1.0, 0.29, 0.2), true)
	neutral_material = _material(Color(0.4, 0.73, 0.92), true)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.018, 0.026, 0.05)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.48, 0.58, 0.72)
	settings.ambient_light_energy = 0.55
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -35, 0)
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	add_child(sun)
	_terrain()
	preview = _box(self, Vector3(CELL_SIZE * 0.96, 0.035, CELL_SIZE * 0.96),
		Vector3.ZERO, good_material)
	preview.visible = false
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func cell_position(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0, cell.y * CELL_SIZE)


static func world_cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / CELL_SIZE), roundi(point.z / CELL_SIZE))


func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.83
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _box(parent: Node3D, size: Vector3, at: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3,
		material: Material, top_ratio: float = 1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * top_ratio
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1972
	_box(self, Vector3(51, 0.6, 51), Vector3(0, -0.4, 0),
		_material(Color(0.25, 0.28, 0.32)))
	var tiles := MultiMesh.new()
	tiles.transform_format = MultiMesh.TRANSFORM_3D
	tiles.use_colors = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL_SIZE - 0.04, 0.08, CELL_SIZE - 0.04)
	tiles.mesh = mesh
	tiles.instance_count = 441
	var index := 0
	for x in range(-10, 11):
		for y in range(-10, 11):
			var ice := x <= -3 and y >= -4 and y <= 4
			var shade := rng.randf_range(0.86, 1.08)
			var color := Color(0.31, 0.46, 0.53) if ice else Color(0.43, 0.45, 0.49)
			tiles.set_instance_transform(index,
				Transform3D(Basis.IDENTITY, cell_position(Vector2i(x, y)) - Vector3(0, 0.05, 0)))
			tiles.set_instance_color(index, Color(color.r * shade, color.g * shade, color.b * shade))
			index += 1
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = tiles
	var material := _material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	instance.material_override = material
	add_child(instance)
	var rock_material := _material(Color(0.28, 0.3, 0.34))
	for i in range(45):
		var angle := rng.randf_range(0, TAU)
		var distance := rng.randf_range(28, 36)
		var radius := rng.randf_range(0.4, 1.7)
		_cylinder(self, radius, radius * 0.6,
			Vector3(cos(angle) * distance, -0.05, sin(angle) * distance),
			rock_material, 0.35)
	for at in [Vector3(28, -0.2, -20), Vector3(-26, -0.2, 23)]:
		var ring := TorusMesh.new()
		ring.inner_radius = 2.3
		ring.outer_radius = 3.1
		ring.rings = 24
		ring.ring_segments = 12
		var crater := MeshInstance3D.new()
		crater.mesh = ring
		crater.material_override = rock_material
		crater.position = at
		crater.scale.y = 0.35
		add_child(crater)


func synchronize(simulation: ColonySimulation) -> void:
	for cell: Vector2i in models.keys():
		if not simulation.buildings.has(cell):
			models[cell].queue_free()
			models.erase(cell)
			indicators.erase(cell)
	for cell: Vector2i in simulation.buildings:
		var building: Dictionary = simulation.buildings[cell]
		if models.has(cell) and models[cell].get_meta("kind") != building["kind"]:
			models[cell].queue_free()
			models.erase(cell)
			indicators.erase(cell)
		if not models.has(cell):
			_create_module(cell, building["kind"])
		indicators[cell].material_override = good_material if building["active"] else bad_material
	sun.light_energy = 0.16 if simulation.is_night() else 1.7
	sun.light_color = Color(0.49, 0.62, 1.0) if simulation.is_night() else Color(1.0, 0.9, 0.76)


func show_preview(cell: Vector2i, valid: bool, enabled: bool) -> void:
	preview.visible = enabled
	preview.position = cell_position(cell) + Vector3(0, 0.08, 0)
	preview.material_override = good_material if valid else bad_material


func _create_module(cell: Vector2i, kind: String) -> void:
	var model := Node3D.new()
	model.set_meta("kind", kind)
	model.position = cell_position(cell)
	add_child(model)
	models[cell] = model
	var color: Color = BuildingCatalog.definition(kind)["color"]
	var hull := _material(color)
	var dark := _material(Color(0.1, 0.15, 0.2))
	var white := _material(Color(0.76, 0.79, 0.82))
	if kind == "link":
		_box(model, Vector3(2.25, 0.18, 0.3), Vector3(0, 0.12, 0), hull)
		_box(model, Vector3(0.3, 0.18, 2.25), Vector3(0, 0.12, 0), hull)
	else:
		_box(model, Vector3(1.95, 0.12, 1.95), Vector3(0, 0.06, 0), dark)
		match kind:
			"solar":
				for x in [-0.5, 0.5]:
					_box(model, Vector3(0.1, 0.65, 0.1), Vector3(x, 0.45, 0), white)
					var panel := _box(model, Vector3(0.9, 0.08, 1.7), Vector3(x, 0.85, 0), hull)
					panel.rotation_degrees.x = -15
					for y in [-0.5, 0.0, 0.5]:
						_box(panel, Vector3(0.86, 0.012, 0.025), Vector3(0, 0.045, y), white)
			"reactor":
				_cylinder(model, 0.62, 1.4, Vector3(0, 0.85, 0), hull, 0.7)
				_cylinder(model, 0.75, 0.12, Vector3(0, 1.2, 0), white)
				for x in [-0.78, 0.78]:
					_box(model, Vector3(0.22, 0.65, 1.4), Vector3(x, 0.5, 0), dark)
			"oxygen", "ice":
				_box(model, Vector3(0.9, 0.8, 1.45), Vector3(0.35, 0.55, 0), hull)
				for y in [-0.45, 0.45]:
					_cylinder(model, 0.26, 1.1, Vector3(-0.5, 0.68, y), white)
				if kind == "ice":
					_box(model, Vector3(0.18, 1.7, 0.18), Vector3(0.3, 1.2, 0), dark)
			"mine":
				_box(model, Vector3(1.4, 0.7, 1.4), Vector3(0, 0.55, 0), hull)
				_cylinder(model, 0.38, 0.8, Vector3(0, 1.15, 0), dark, 0.6)
				_box(model, Vector3(0.5, 0.3, 1.9), Vector3(0.7, 0.4, 0), white)
			_:
				_box(model, Vector3(1.65, 0.85, 1.4), Vector3(0, 0.63, 0), hull)
				_box(model, Vector3(1.3, 0.16, 1.5), Vector3(0, 1.13, 0), white)
				for x in [-0.45, 0.0, 0.45]:
					_box(model, Vector3(0.22, 0.25, 0.035), Vector3(x, 0.78, -0.72),
						neutral_material)
				if kind == "lab":
					_cylinder(model, 0.18, 0.8, Vector3(0.5, 1.55, 0.3), white)
					_cylinder(model, 0.38, 0.12, Vector3(0.5, 1.95, 0.3), hull, 0.4)
	indicators[cell] = _box(model, Vector3(0.3, 0.05, 0.15),
		Vector3(0, 0.16, -0.98), good_material)
