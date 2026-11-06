shader_type spatial;
// Island ground: two CC0 PBR sets (dirt, rocky gravel) blended by a low-frequency mask that also breaks
// up the visible repeat. The mesh's vertex colour keeps the sand / jungle / wet-sand tones the generator
// paints; the textures add grain and (on desktop) a normal map. Only the set that is visible is sampled
// where the mask is at an extreme, which keeps the cost down on integrated GPUs.
// use_maps = false is the web / mobile fallback (albedo only). Compatibility-safe.
uniform sampler2D dirt_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float tile_scale = 0.24;
uniform float mask_scale = 0.013;
uniform float detail_strength = 0.62;
uniform float normal_strength = 1.0;
uniform bool use_maps = true;
varying vec2 wxz;

void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = wxz * tile_scale;
	float mask = smoothstep(0.38, 0.62, texture(rock_albedo, wxz * mask_scale).r * 1.15) * 0.85;
	vec3 tex;
	vec3 nrm = vec3(0.5, 0.5, 1.0);
	if (mask < 0.03) {
		tex = texture(dirt_albedo, p).rgb;
		if (use_maps) { nrm = texture(dirt_normal, p).rgb; }
	} else if (mask > 0.82) {
		tex = texture(rock_albedo, p).rgb;
		if (use_maps) { nrm = texture(rock_normal, p).rgb; }
	} else {
		tex = mix(texture(dirt_albedo, p).rgb, texture(rock_albedo, p).rgb, mask);
		if (use_maps) { nrm = mix(texture(dirt_normal, p).rgb, texture(rock_normal, p).rgb, mask); }
	}
	float lum = dot(tex, vec3(0.333));
	ALBEDO = mix(COLOR.rgb * 0.42, tex * 0.85, 0.55) * clamp(lum / 0.3, 0.6, 1.1);
	if (use_maps) {
		NORMAL_MAP = nrm;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
