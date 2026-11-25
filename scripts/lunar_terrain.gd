class_name LunarTerrain
extends RefCounted

## CPU-side heightfield for the lunar site. Heights drive both the GPU displacement
## textures and gameplay queries (building pad heights, cursor picking). Grading
## (bulldozing) writes into the live heights and the graded mask, which the regolith
## shader renders as compacted, darker ground with tread marks.

const SIZE := 128.0
const RESOLUTION := 1024
const TEXEL := SIZE / RESOLUTION
const SITE_HALF := 26.0
const FEATHER := 0.5

var base_heights := PackedFloat32Array()
var heights := PackedFloat32Array()
var halo := PackedFloat32Array()
var grade_mask := PackedFloat32Array()
var base_surface := PackedByteArray()
var craters: Array[Vector4] = []
var pad_targets: Dictionary = {}
var height_image: Image
var surface_image: Image
var height_texture: ImageTexture
var surface_texture: ImageTexture
var detail_normal: ImageTexture
var detail_albedo: ImageTexture
var _dirty := false


func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	base_heights = _macro_relief(seed_value)
	halo.resize(RESOLUTION * RESOLUTION)
	halo.fill(0.0)
	craters.clear()
	for crater in SiteSurvey.LANDMARK_CRATERS:
		_add_crater(crater.x, crater.y, crater.z, 0.82 if crater.z > 5.0 else 0.45, rng)
	for i in range(9):
		var at := _random_point(rng, 30.0)
		_add_crater(at.x, at.y, rng.randf_range(3.0, 7.5), rng.randf_range(0.3, 0.75), rng)
	for i in range(230):
		var at := _random_point(rng, 0.0)
		_add_crater(at.x, at.y, 0.8 + 1.9 * pow(rng.randf(), 2.2), _freshness(rng), rng)
	for i in range(2600):
		var at := _random_point(rng, 0.0)
		_add_crater(at.x, at.y, 0.3 + 0.5 * pow(rng.randf(), 2.0), _freshness(rng), rng)
	for crater in craters:
		_stamp_crater(crater, rng)
	_fade_border()
	_build_base_surface()
	_build_detail(seed_value)
	restore()


func restore() -> void:
	heights = base_heights.duplicate()
	grade_mask.resize(RESOLUTION * RESOLUTION)
	grade_mask.fill(0.0)
	pad_targets.clear()
	height_image = Image.create_from_data(RESOLUTION, RESOLUTION, false, Image.FORMAT_RF,
		heights.to_byte_array())
	height_image.convert(Image.FORMAT_RH)
	surface_image = Image.create_from_data(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8,
		base_surface)
	if height_texture == null:
		height_texture = ImageTexture.create_from_image(height_image)
		surface_texture = ImageTexture.create_from_image(surface_image)
	else:
		height_texture.update(height_image)
		surface_texture.update(surface_image)
	_dirty = false


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / TEXEL - 0.5, 0.0, RESOLUTION - 1.001)
	var fz := clampf((z + SIZE * 0.5) / TEXEL - 0.5, 0.0, RESOLUTION - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * RESOLUTION + ix
	var top := lerpf(heights[i], heights[i + 1], tx)
	var bottom := lerpf(heights[i + RESOLUTION], heights[i + RESOLUTION + 1], tx)
	return lerpf(top, bottom, tz)


func pad_height(cell: Vector2i, cell_size: float) -> float:
	if pad_targets.has(cell):
		return pad_targets[cell]
	return height_at(cell.x * cell_size, cell.y * cell_size)


## Flattens a cell to a level pad. Feathers into rough neighbours but never into
## other graded pads, so adjacent pads keep their own levels.
func grade(cell: Vector2i, cell_size: float) -> void:
	if pad_targets.has(cell):
		return
	var center := Vector2(cell.x, cell.y) * cell_size
	var half := cell_size * 0.5
	var total := 0.0
	var samples := 0
	var low := _texel_index(center.x - half - FEATHER, center.y - half - FEATHER)
	var high := _texel_index(center.x + half + FEATHER, center.y + half + FEATHER)
	for py in range(low.y, high.y + 1):
		for px in range(low.x, high.x + 1):
			var world := _texel_world(px, py)
			if absf(world.x - center.x) <= half and absf(world.y - center.y) <= half:
				total += heights[py * RESOLUTION + px]
				samples += 1
	var target := total / maxi(samples, 1)
	var neighbours := 0
	var neighbour_total := 0.0
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if pad_targets.has(cell + offset):
			neighbour_total += pad_targets[cell + offset]
			neighbours += 1
	if neighbours > 0:
		target = lerpf(target, neighbour_total / neighbours, 0.6)
	for py in range(low.y, high.y + 1):
		for px in range(low.x, high.x + 1):
			var world := _texel_world(px, py)
			var outside := maxf(absf(world.x - center.x) - half, absf(world.y - center.y) - half)
			var weight := 1.0 - smoothstep(0.0, FEATHER, outside)
			var i := py * RESOLUTION + px
			if weight <= 0.0 or (weight < 1.0 and grade_mask[i] >= 0.999):
				continue
			heights[i] = lerpf(heights[i], target, weight) + 0.28 * weight * (1.0 - weight)
			grade_mask[i] = maxf(grade_mask[i], weight)
			height_image.set_pixel(px, py, Color(heights[i], 0, 0))
			var surface := surface_image.get_pixel(px, py)
			surface.g = grade_mask[i]
			surface_image.set_pixel(px, py, surface)
	pad_targets[cell] = target
	_dirty = true


func upload() -> void:
	if _dirty:
		height_texture.update(height_image)
		surface_texture.update(surface_image)
		_dirty = false


func _texel_index(x: float, z: float) -> Vector2i:
	return Vector2i(
		clampi(int((x + SIZE * 0.5) / TEXEL), 0, RESOLUTION - 1),
		clampi(int((z + SIZE * 0.5) / TEXEL), 0, RESOLUTION - 1))


func _texel_world(px: int, py: int) -> Vector2:
	return Vector2((px + 0.5) * TEXEL - SIZE * 0.5, (py + 0.5) * TEXEL - SIZE * 0.5)


func _random_point(rng: RandomNumberGenerator, min_extent: float) -> Vector2:
	var limit := SIZE * 0.5 - 4.0
	while true:
		var at := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		if maxf(absf(at.x), absf(at.y)) >= min_extent:
			return at
	return Vector2.ZERO


## Most craters are old and degraded; few keep sharp rims and bright ejecta.
func _freshness(rng: RandomNumberGenerator) -> float:
	var roll := rng.randf()
	if roll < 0.62:
		return rng.randf() * 0.3
	if roll < 0.82:
		return rng.randf_range(0.3, 0.7)
	return rng.randf_range(0.75, 1.0)


func _add_crater(x: float, z: float, radius: float, freshness: float,
		_rng: RandomNumberGenerator) -> void:
	craters.append(Vector4(x, z, radius, freshness))


func _macro_relief(seed_value: int) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 26.0
	noise.fractal_octaves = 5
	var broad := FastNoiseLite.new()
	broad.seed = seed_value + 17
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.frequency = 1.0 / 90.0
	broad.fractal_octaves = 2
	var grid := 257
	var coarse := PackedFloat32Array()
	coarse.resize(grid * grid)
	for gy in range(grid):
		for gx in range(grid):
			var x := (float(gx) / (grid - 1) - 0.5) * SIZE
			var z := (float(gy) / (grid - 1) - 0.5) * SIZE
			var outer := smoothstep(SITE_HALF, SITE_HALF + 16.0, maxf(absf(x), absf(z)))
			coarse[gy * grid + gx] = (
				noise.get_noise_2d(x, z) * lerpf(0.35, 1.2, outer)
				+ broad.get_noise_2d(x, z) * lerpf(0.4, 2.6, outer)
			)
	var image := Image.create_from_data(grid, grid, false, Image.FORMAT_RF, coarse.to_byte_array())
	image.resize(RESOLUTION, RESOLUTION, Image.INTERPOLATE_CUBIC)
	return image.get_data().to_float32_array()


func _stamp_crater(crater: Vector4, rng: RandomNumberGenerator) -> void:
	var radius := crater.z
	var fresh := crater.w
	var depth := radius * lerpf(0.07, 0.32, fresh)
	var rim := radius * lerpf(0.012, 0.085, fresh)
	var reach := lerpf(1.7, 2.6, fresh)
	var phase := rng.randf() * TAU
	var phase_two := rng.randf() * TAU
	var lobes := float(rng.randi_range(2, 4))
	var rays := float(rng.randi_range(5, 12))
	var bright := clampf((fresh - 0.55) / 0.45, 0.0, 1.0)
	var low := _texel_index(crater.x - radius * reach, crater.y - radius * reach)
	var high := _texel_index(crater.x + radius * reach, crater.y + radius * reach)
	var floor_level := -depth * lerpf(0.75, 1.0, clampf(1.6 - radius * 0.4, 0.0, 1.0))
	for py in range(low.y, high.y + 1):
		for px in range(low.x, high.x + 1):
			var world := _texel_world(px, py)
			var dx := world.x - crater.x
			var dz := world.y - crater.y
			var angle := atan2(dz, dx)
			var wobble := 1.0 + 0.05 * sin(angle * lobes + phase) + 0.03 * sin(angle * 7.0 + phase_two)
			var d := sqrt(dx * dx + dz * dz) / (radius * wobble)
			if d >= reach:
				continue
			var h: float
			if d < 1.0:
				var fresh_bowl := maxf(depth * (d * d - 1.0), floor_level) + rim * pow(d, 4.0)
				var soft_bowl := (-depth * 0.5 * (1.0 + cos(PI * d))) + rim * d * d
				h = lerpf(soft_bowl, fresh_bowl, fresh)
			else:
				var t := (d - 1.0) / (reach - 1.0)
				h = rim * pow(d, -3.0) * (1.0 - smoothstep(0.0, 1.0, t))
			var i := py * RESOLUTION + px
			base_heights[i] += h
			if bright > 0.0:
				var glow: float
				if d < 1.0:
					glow = 0.45 * smoothstep(0.25, 1.0, d)
				else:
					var ray := pow(absf(sin(angle * rays * 0.5 + phase)), 4.0)
					glow = exp(-(d - 1.0) * 2.0) * (0.35 + 0.65 * ray) * (1.0 - smoothstep(reach * 0.8, reach, d))
				halo[i] += glow * bright


func _fade_border() -> void:
	for py in range(RESOLUTION):
		for px in range(RESOLUTION):
			var world := _texel_world(px, py)
			var edge := maxf(absf(world.x), absf(world.y))
			if edge > SIZE * 0.5 - 10.0:
				base_heights[py * RESOLUTION + px] *= 1.0 - smoothstep(SIZE * 0.5 - 10.0, SIZE * 0.5 - 1.0, edge)


func _build_base_surface() -> void:
	base_surface.resize(RESOLUTION * RESOLUTION * 4)
	for i in range(RESOLUTION * RESOLUTION):
		base_surface[i * 4] = clampi(int(128.0 + clampf(halo[i], -1.0, 1.0) * 127.0), 0, 255)
		base_surface[i * 4 + 1] = 0
		base_surface[i * 4 + 2] = 0
		base_surface[i * 4 + 3] = 255


## Tiling micro relief (tiny craters plus roughness) and albedo mottling used by
## the regolith shader for detail below the heightfield resolution.
func _build_detail(seed_value: int) -> void:
	var size := 512
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + 3
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 6
	var rough := noise.get_seamless_image(size, size, false, false, 0.2)
	rough.convert(Image.FORMAT_RF)
	rough.resize(size / 2, size / 2, Image.INTERPOLATE_BILINEAR)
	rough.resize(size, size, Image.INTERPOLATE_CUBIC)
	var micro := rough.get_data().to_float32_array()
	for i in range(micro.size()):
		micro[i] *= 6.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 11
	for n in range(900):
		var cx := rng.randf() * size
		var cy := rng.randf() * size
		var radius := 1.5 / pow(1.0 - rng.randf() * 0.985, 0.55)
		radius = minf(radius, 22.0)
		var fresh := pow(rng.randf(), 3.0)
		var depth := radius * lerpf(0.05, 0.3, fresh)
		var rim := radius * lerpf(0.005, 0.06, fresh)
		var reach := radius * 2.0
		for oy in range(int(-reach), int(reach) + 1):
			for ox in range(int(-reach), int(reach) + 1):
				var d := sqrt(float(ox * ox + oy * oy)) / radius
				if d >= 2.0:
					continue
				var sharp := depth * (d * d - 1.0) + rim * pow(d, 4.0) if d < 1.0 else (
					rim * pow(d, -3.0) * (2.0 - d))
				var soft := -depth * 0.5 * (1.0 + cos(PI * minf(d, 1.0))) + rim * exp(-pow((d - 1.0) * 3.0, 2.0))
				var h := lerpf(soft, sharp, fresh)
				var px := posmod(int(cx) + ox, size)
				var py := posmod(int(cy) + oy, size)
				micro[py * size + px] += h
	var normal := Image.create_from_data(size, size, false, Image.FORMAT_RF, micro.to_byte_array())
	normal.bump_map_to_normal_map(1.0)
	normal.generate_mipmaps()
	detail_normal = ImageTexture.create_from_image(normal)
	var mottling := FastNoiseLite.new()
	mottling.seed = seed_value + 5
	mottling.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mottling.frequency = 0.03
	mottling.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mottling.fractal_octaves = 5
	var albedo := mottling.get_seamless_image(size, size, false, false, 0.2)
	albedo.convert(Image.FORMAT_RGBA8)
	albedo.generate_mipmaps()
	detail_albedo = ImageTexture.create_from_image(albedo)
