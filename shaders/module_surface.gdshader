shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.82, 0.79, 0.68, 1.0);
uniform bool solar_cells = false;

void fragment() {
	if (solar_cells) {
		vec2 cell = fract(UV * vec2(8.0, 16.0));
		float interior = step(0.055, cell.x) * step(cell.x, 0.945)
			* step(0.045, cell.y) * step(cell.y, 0.955);
		float conductor = 1.0 - step(0.014, abs(cell.x - 0.5));
		ALBEDO = mix(vec3(0.36, 0.40, 0.44), base_color.rgb, interior);
		ALBEDO = mix(ALBEDO, vec3(0.53, 0.59, 0.67), conductor * 0.65);
		METALLIC = 0.65;
		ROUGHNESS = 0.28;
	} else {
		vec2 quilt = abs(fract(UV * vec2(12.0, 8.0)) - 0.5);
		float seam = smoothstep(0.43, 0.49, max(quilt.x, quilt.y));
		float wrinkle = sin(UV.x * 110.0 + sin(UV.y * 45.0) * 3.0)
			* sin(UV.y * 85.0 + UV.x * 15.0);
		ALBEDO = base_color.rgb * (0.91 + wrinkle * 0.035 - seam * 0.18);
		NORMAL_MAP = normalize(vec3(wrinkle * 0.045, seam * 0.08, 1.0)) * 0.5 + 0.5;
		METALLIC = 0.55;
		ROUGHNESS = 0.58;
	}
}
