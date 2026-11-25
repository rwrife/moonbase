class_name LunarSite
extends Node3D

const CELL_SIZE := 2.3
const TERRAIN_SEED := 1972
const SUN_ROTATION := Vector3(-22.0, -90.0, 0.0)
const DAY_COLOR := Color(1.0, 0.985, 0.96)
const DAY_ENERGY := 3.2
const REGOLITH_SHADER := preload("res://shaders/regolith.gdshader")

var terrain: LunarTerrain
var terrain_material: ShaderMaterial
var overlay_image: Image
var overlay_texture: ImageTexture
var rock_material: StandardMaterial3D
## Cell -> Array of [MultiMesh, instance index, Transform3D, sink] for clearable rocks.
var cell_rocks: Dictionary = {}
var hidden_rocks: Dictionary = {}
var boulders: Array[MeshInstance3D] = []
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
	for material in [good_material, bad_material]:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.42
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.003, 0.004, 0.007)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.78, 0.78, 0.8)
	settings.ambient_light_energy = 0.09
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	settings.tonemap_exposure = 1.05
	# Airless sky: no fog/haze; a touch of extra contrast keeps the vacuum look crisp.
	settings.fog_enabled = false
	settings.adjustment_enabled = true
	settings.adjustment_contrast = 1.18
	environment.environment = settings
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = SUN_ROTATION
	sun.light_color = DAY_COLOR
	sun.light_energy = DAY_ENERGY
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.8
	sun.shadow_blur = 0.35
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	terrain = LunarTerrain.new()
	terrain.generate(TERRAIN_SEED)
	_terrain()
	_scatter_rocks()
	_boulders()
	preview = _box(self, Vector3(CELL_SIZE * 0.96, 0.05, CELL_SIZE * 0.96),
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
	overlay_image = Image.create(21, 21, false, Image.FORMAT_RGBA8)
	overlay_texture = ImageTexture.create_from_image(overlay_image)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = REGOLITH_SHADER
	terrain_material.set_shader_parameter("height_tex", terrain.height_texture)
	terrain_material.set_shader_parameter("surface_tex", terrain.surface_texture)
	terrain_material.set_shader_parameter("overlay_tex", overlay_texture)
	terrain_material.set_shader_parameter("detail_normal", terrain.detail_normal)
	terrain_material.set_shader_parameter("detail_albedo", terrain.detail_albedo)
	terrain_material.set_shader_parameter("terrain_size", LunarTerrain.SIZE)
	terrain_material.set_shader_parameter("texel", LunarTerrain.TEXEL)
	terrain_material.set_shader_parameter("cell_size", CELL_SIZE)
	terrain_material.set_shader_parameter("map_radius", float(ColonySimulation.MAP_RADIUS))
	terrain_material.set_shader_parameter("sun_dir", sun.global_basis.z.normalized())
	var plane := PlaneMesh.new()
	plane.size = Vector2(LunarTerrain.SIZE, LunarTerrain.SIZE)
	plane.subdivide_width = 511
	plane.subdivide_depth = 511
	var ground := MeshInstance3D.new()
	ground.name = "Regolith"
	ground.mesh = plane
	ground.material_override = terrain_material
	ground.extra_cull_margin = 8.0
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var skirt_material: ShaderMaterial = terrain_material.duplicate()
	skirt_material.set_shader_parameter("far_mode", 1.0)
	var far := PlaneMesh.new()
	far.size = Vector2(700, 700)
	var skirt := MeshInstance3D.new()
	skirt.name = "FarRegolith"
	skirt.mesh = far
	skirt.material_override = skirt_material
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)


## Irregular faceted rock: a jittered low-poly sphere with a flattened, buried base.
func _rock_mesh(seed_value: int, segments: int, rings: int, smooth: bool = false) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	var sphere := SphereMesh.new()
	sphere.radial_segments = segments
	sphere.rings = rings
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stretch := Vector3(rng.randf_range(0.8, 1.25), rng.randf_range(0.5, 0.85),
		rng.randf_range(0.75, 1.15))
	# Random plane cuts chip the blob into flat, angular fracture faces.
	var cuts: Array[Plane] = []
	for i in range(rng.randi_range(7, 12)):
		var normal := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		cuts.append(Plane(normal, rng.randf_range(0.26, 0.42)))
	for i in range(vertices.size()):
		var direction := vertices[i].normalized()
		var radius := 0.5 * (1.0 + 0.42 * noise.get_noise_3dv(direction * 1.3)
			+ 0.12 * noise.get_noise_3dv(direction * 4.0 + Vector3(9, 3, 1))
			+ 0.05 * noise.get_noise_3dv(direction * 11.0 + Vector3(2, 7, 5)))
		var v := direction * radius * stretch
		for cut in cuts:
			var excess := cut.distance_to(v)
			if excess > 0.0:
				v -= cut.normal * excess
		if v.y < -0.12:
			v.y = -0.12 + (v.y + 0.12) * 0.35
		vertices[i] = v
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if smooth:
		for i in range(indices.size()):
			tool.add_vertex(vertices[indices[i]])
		tool.index()
		tool.generate_normals()
		return tool.commit()
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 0.0000001:
			continue
		tool.set_normal(normal.normalized())
		for v in [a, b, c]:
			tool.add_vertex(v)
	return tool.commit()


func _scatter_rocks() -> void:
	rock_material = StandardMaterial3D.new()
	rock_material.vertex_color_use_as_albedo = true
	rock_material.albedo_color = Color(0.85, 0.85, 0.83)
	rock_material.albedo_texture = terrain.detail_albedo
	rock_material.normal_enabled = true
	rock_material.normal_texture = terrain.detail_normal
	rock_material.normal_scale = 0.8
	rock_material.uv1_triplanar = true
	rock_material.uv1_world_triplanar = true
	rock_material.uv1_scale = Vector3.ONE * 0.6
	rock_material.roughness = 1.0
	rock_material.metallic_specular = 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = TERRAIN_SEED + 99
	var limit := LunarTerrain.SIZE * 0.5 - 3.0
	var placements: Array = [[], [], [], [], []]
	# Pebble field: mostly uniform with clustering near fresh crater rims.
	for i in range(4500):
		var at := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		placements[3 + i % 2].append([at, rng.randf_range(0.04, 0.12) * (1.0 + pow(rng.randf(), 6.0) * 1.5)])
	for crater in terrain.craters:
		if crater.w < 0.35:
			continue
		var count := int(crater.z * crater.z * crater.w * 9.0) + rng.randi_range(2, 6)
		for i in range(mini(count, 160)):
			var angle := rng.randf() * TAU
			var distance := crater.z * (0.65 + pow(rng.randf(), 1.8) * 1.4)
			var at := Vector2(crater.x, crater.y) + Vector2(cos(angle), sin(angle)) * distance
			if absf(at.x) > limit or absf(at.y) > limit:
				continue
			var size := lerpf(0.08, 0.32, pow(rng.randf(), 2.2)) * clampf(crater.z * 0.6, 0.6, 2.2)
			placements[i % 3].append([at, size])
			if rng.randf() < 0.8:
				placements[3 + i % 2].append([at + Vector2(rng.randf_range(-0.6, 0.6),
					rng.randf_range(-0.6, 0.6)), rng.randf_range(0.04, 0.1)])
	for i in range(220):
		var at := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		placements[i % 3].append([at, lerpf(0.1, 0.45, pow(rng.randf(), 3.0))])
	for variant in range(5):
		var pebble := variant >= 3
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _rock_mesh(TERRAIN_SEED + variant * 13, 6 if pebble else 9,
			4 if pebble else 6)
		var list: Array = placements[variant]
		multimesh.instance_count = list.size()
		for index in range(list.size()):
			var at: Vector2 = list[index][0]
			var size: float = list[index][1]
			var sink := size * rng.randf_range(0.05, 0.3)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(
				Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(),
				rng.randf_range(0.0, 0.35)).scaled(Vector3.ONE * size)
			var transform := Transform3D(basis, Vector3(at.x, terrain.height_at(at.x, at.y) - sink, at.y))
			multimesh.set_instance_transform(index, transform)
			var shade := rng.randf_range(0.72, 1.22)
			multimesh.set_instance_color(index, Color(shade, shade * 0.99, shade * 0.97))
			var cell := world_cell(transform.origin)
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var near := cell + Vector2i(dx, dy)
					var center := cell_position(near)
					var reach := CELL_SIZE * 0.5 + LunarTerrain.FEATHER * 0.5 + size * 0.4
					if absf(at.x - center.x) <= reach and absf(at.y - center.z) <= reach:
						if not cell_rocks.has(near):
							cell_rocks[near] = []
						cell_rocks[near].append([multimesh, index, transform, sink])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Pebbles%d" % variant if pebble else "Rocks%d" % variant
		instance.multimesh = multimesh
		instance.material_override = rock_material
		if pebble:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)


func _boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TERRAIN_SEED + 7
	var spots: Array[Vector3] = SiteSurvey.BOULDERS.duplicate()
	while spots.size() < 22:
		var at := Vector2(rng.randf_range(-58, 58), rng.randf_range(-58, 58))
		if maxf(absf(at.x), absf(at.y)) > 27.0:
			spots.append(Vector3(at.x, at.y, rng.randf_range(0.5, 1.2)))
	for index in range(spots.size()):
		var spot := spots[index]
		var boulder := MeshInstance3D.new()
		boulder.name = "Boulder%d" % index
		boulder.mesh = _rock_mesh(TERRAIN_SEED + 500 + index, 22, 13)
		boulder.material_override = rock_material
		var size := spot.z * 1.6
		boulder.basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.9, size))
		boulder.position = Vector3(spot.x, terrain.height_at(spot.x, spot.y) - size * 0.22, spot.y)
		add_child(boulder)
		boulders.append(boulder)


func pad_height(cell: Vector2i) -> float:
	return terrain.pad_height(cell, CELL_SIZE)


func surface_position(cell: Vector2i) -> Vector3:
	return cell_position(cell) + Vector3(0, pad_height(cell), 0)


func _sync_terrain(simulation: ColonySimulation) -> void:
	var stale := false
	for cell: Vector2i in terrain.pad_targets:
		if not simulation.graded.has(cell):
			stale = true
	if stale:
		terrain.restore()
		hidden_rocks.clear()
		for cell: Vector2i in cell_rocks:
			for entry: Array in cell_rocks[cell]:
				entry[0].set_instance_transform(entry[1], entry[2])
	for cell: Vector2i in simulation.graded:
		if terrain.pad_targets.has(cell):
			continue
		terrain.grade(cell, CELL_SIZE)
		for entry: Array in cell_rocks.get(cell, []):
			var hidden: Transform3D = entry[2]
			hidden_rocks[[entry[0], entry[1]]] = true
			entry[0].set_instance_transform(entry[1], Transform3D(Basis().scaled(Vector3.ZERO), hidden.origin))
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var near := cell + Vector2i(dx, dy)
				if near == cell or simulation.graded.has(near):
					continue
				for entry: Array in cell_rocks.get(near, []):
					if hidden_rocks.has([entry[0], entry[1]]):
						continue
					var moved: Transform3D = entry[2]
					moved.origin.y = terrain.height_at(moved.origin.x, moved.origin.z) - entry[3]
					entry[0].set_instance_transform(entry[1], moved)
	terrain.upload()
	for x in range(21):
		for y in range(21):
			var cell := Vector2i(x - 10, y - 10)
			overlay_image.set_pixel(x, y, Color(
				1.0 if simulation.has_ice(cell) else 0.0,
				1.0 if simulation.blocked.has(cell) else 0.0,
				1.0 if simulation.graded.has(cell) else 0.0))
	overlay_texture.update(overlay_image)


func set_overlay(enabled: bool) -> void:
	terrain_material.set_shader_parameter("overlay_strength", 1.0 if enabled else 0.0)


func synchronize(simulation: ColonySimulation) -> void:
	_sync_terrain(simulation)
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
		models[cell].position = surface_position(cell)
		indicators[cell].material_override = good_material if building["active"] else bad_material
	sun.light_energy = 0.22 if simulation.is_night() else DAY_ENERGY
	sun.light_color = Color(0.55, 0.66, 1.0) if simulation.is_night() else DAY_COLOR


func show_preview(cell: Vector2i, valid: bool, enabled: bool) -> void:
	preview.visible = enabled
	preview.position = surface_position(cell) + Vector3(0, 0.06, 0)
	preview.material_override = good_material if valid else bad_material


func _create_module(cell: Vector2i, kind: String) -> void:
	var model := Node3D.new()
	model.set_meta("kind", kind)
	model.position = surface_position(cell)
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
