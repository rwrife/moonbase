shader_type spatial;
render_mode cull_back, specular_disabled;

// Heightfield-displaced lunar regolith with analytic normals, ray-marched terrain
// self-shadowing, crater albedo halos, bulldozer grading and a build-mode overlay.

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D surface_tex : filter_linear, repeat_disable;
uniform sampler2D overlay_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float terrain_size = 128.0;
uniform float texel = 0.125;
uniform vec3 sun_dir = vec3(0.7, 0.3, 0.1);
uniform float far_mode = 0.0;
uniform float overlay_strength = 0.0;
uniform float cell_size = 2.3;
uniform float map_radius = 10.0;
uniform vec4 ice_zone = vec4(-10.0, -4.0, -3.0, 4.0);
uniform float albedo_base = 0.3;
uniform float detail_strength = 1.0;
uniform float lommel_mix = 0.6;

varying vec3 world_pos;
varying float sun_vis;

float terrain_h(vec2 xz) {
	return textureLod(height_tex, xz / terrain_size + 0.5, 0.0).r;
}

vec2 detail_slope(vec2 uv, float strength) {
	vec3 n = texture(detail_normal, uv).rgb * 2.0 - 1.0;
	return vec2(-n.x, n.y) / max(n.z, 0.25) * strength;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = far_mode > 0.5 ? 0.0 : terrain_h(wp.xz);
	VERTEX.y += h;
	world_pos = wp + vec3(0.0, h, 0.0);
}

void fragment() {
	vec2 xz = world_pos.xz;
	float half_size = terrain_size * 0.5;
	if (far_mode > 0.5 && max(abs(xz.x), abs(xz.y)) < half_size - 0.25) {
		discard;
	}
	vec2 uv = xz / terrain_size + 0.5;
	float h0 = 0.0;
	vec2 slope = vec2(0.0);
	vec4 surface = vec4(0.5, 0.0, 0.0, 1.0);
	if (far_mode < 0.5) {
		h0 = terrain_h(xz);
		float e = texel;
		slope = vec2(
			terrain_h(xz + vec2(e, 0.0)) - terrain_h(xz - vec2(e, 0.0)),
			terrain_h(xz + vec2(0.0, e)) - terrain_h(xz - vec2(0.0, e))) / (2.0 * e);
		surface = texture(surface_tex, uv);
	}
	float graded = smoothstep(0.05, 0.9, surface.g);
	float rough = (1.0 - graded * 0.55) * detail_strength;
	mat2 turn_a = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	mat2 turn_b = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28));
	slope += detail_slope(xz / 13.0, 0.2) * rough;
	slope += turn_a * detail_slope(turn_a * xz / 5.3 + vec2(0.37, 0.71), 0.17) * rough;
	slope += turn_b * detail_slope(turn_b * xz / 1.7 + vec2(0.13, 0.52), 0.13) * rough;
	slope += turn_a * detail_slope(turn_b * xz / 0.55 + vec2(0.61, 0.29), 0.07) * rough;
	// Bulldozer tread grooves and blade ridges on graded pads.
	float groove = sin(xz.x * 21.0) + 0.5 * sin(xz.x * 47.0 + 1.3);
	float pad_center = step(0.98, surface.g);
	float tread = sin(xz.x * 22.0 + (texture(detail_albedo, xz / 2.3).r - 0.5) * 3.0);
	slope.x += graded * pad_center * 0.04 * sign(tread) * smoothstep(0.0, 0.3, abs(tread));
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float broad = texture(detail_albedo, xz / 57.0).r;
	float mid = texture(detail_albedo, xz / 17.0 + vec2(0.21, 0.6)).r;
	vec2 streak_uv = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * xz;
	float streak = texture(detail_albedo, streak_uv * vec2(0.018, 0.045)).r;
	float fine = texture(detail_albedo, xz / 2.3 + vec2(0.5, 0.17)).r;
	float grain = texture(detail_albedo, turn_a * xz / 0.45 + vec2(0.17, 0.9)).r;
	float halo = surface.r * 2.0 - 1.0;
	// No atmosphere: no haze softening, so keep fine grain crisp and broad mottling restrained.
	float albedo = albedo_base * (0.92 + 0.06 * broad + 0.04 * (mid - 0.5) + 0.06 * (streak - 0.5)
		+ 0.1 * (fine - 0.5) + 0.22 * (grain - 0.5));
	// Slope-dependent micro contrast: steep crater walls expose brighter, fresher regolith.
	albedo *= 1.0 + clamp(length(slope) - 0.25, 0.0, 0.6) * 0.35;
	albedo *= 1.0 + halo * 0.5;
	albedo *= 1.0 - graded * 0.1 + graded * pad_center * 0.015 * groove;
	vec3 color = vec3(albedo) * vec3(1.0, 0.995, 0.985);

	vec2 cell = xz / cell_size;
	vec2 ice_low = ice_zone.xy - 0.5;
	vec2 ice_high = ice_zone.zw + 0.5;
	float ice_edge = min(min(cell.x - ice_low.x, ice_high.x - cell.x), min(cell.y - ice_low.y, ice_high.y - cell.y));
	float ice = smoothstep(-0.6, 0.6, ice_edge + (mid - 0.5) * 1.6);
	float frost = ice * (0.35 + 0.65 * smoothstep(0.35, 0.75, fine * 0.5 + mid * 0.6)) * (1.0 - graded * 0.6);
	color = mix(color, color * vec3(0.97, 1.0, 1.05), frost * 0.6);

	if (overlay_strength > 0.0 && far_mode < 0.5) {
		vec2 ci = round(cell);
		if (max(abs(ci.x), abs(ci.y)) <= map_radius) {
			vec2 f = abs(cell - ci);
			float line = smoothstep(0.47, 0.492, max(f.x, f.y)) * 0.7;
			vec4 info = texture(overlay_tex, (ci + map_radius + 0.5) / (2.0 * map_radius + 1.0));
			vec3 tint = vec3(0.0);
			float amount = 0.0;
			if (info.r > 0.5) {
				tint = vec3(0.2, 0.55, 1.0);
				amount = 0.35;
			}
			if (info.b > 0.5) {
				tint = vec3(0.35, 0.95, 0.65);
				amount = 0.18;
			}
			if (info.g > 0.5) {
				tint = vec3(1.0, 0.28, 0.18);
				amount = 0.4;
			}
			color = mix(color, tint * 0.5, amount * overlay_strength);
			EMISSION = (tint * amount * 0.12 + vec3(0.15, 0.55, 0.65) * line * 0.5) * overlay_strength;
			color = mix(color, vec3(0.3, 0.75, 0.85), line * 0.5 * overlay_strength);
		}
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	sun_vis = 1.0;
	if (far_mode < 0.5 && sun_dir.y > 0.005) {
		vec2 dir = normalize(sun_dir.xz);
		float rise = sun_dir.y / max(length(sun_dir.xz), 0.001);
		// Interleaved-gradient jitter hides step banding; fine steps keep rims sharp.
		float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		float t = texel * (0.5 + jitter * 0.6);
		float start = h0 + 0.006;
		for (int i = 0; i < 56; i++) {
			float occluder = terrain_h(xz + dir * t);
			float above = occluder - (start + rise * t);
			sun_vis = min(sun_vis, 1.0 - smoothstep(-0.003, 0.006 + 0.0015 * t, above));
			t *= 1.11;
		}
	}
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Lunar regolith: Lommel-Seeliger backscatter blended with Lambert, no specular.
	float lommel = 2.0 * nl / (nl + nv + 0.0001);
	float brdf = mix(nl, lommel * 0.5, lommel_mix);
	DIFFUSE_LIGHT += brdf * ATTENUATION * LIGHT_COLOR * sun_vis / PI;
	// Light bounced off sunlit crater walls and the surrounding plain.
	DIFFUSE_LIGHT += (0.03 + 0.045 * (1.0 - sun_vis)) * LIGHT_COLOR * clamp(dot(NORMAL, VIEW), 0.3, 1.0) / PI;
}
