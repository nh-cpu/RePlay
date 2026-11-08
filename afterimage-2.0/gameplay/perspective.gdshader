shader_type canvas_item;
render_mode unshaded;

uniform float distant_width : hint_range(0.2, 0.8) = 0.38;

void fragment() {
	// Inverse planar perspective keeps long hold bodies continuous with their heads.
	float width_at_y = distant_width + (1.0 - distant_width) * UV.y;
	vec2 source_uv = vec2((UV.x - 0.5) / width_at_y + 0.5, UV.y / width_at_y);
	if (source_uv.x < 0.0 || source_uv.x > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec4 lane = texture(TEXTURE, source_uv);
		float depth_light = mix(0.48, 1.0, smoothstep(0.0, 0.8, UV.y));
		float edge = 1.0 - smoothstep(0.002, 0.006, min(source_uv.x, 1.0 - source_uv.x));
		lane.rgb = lane.rgb * depth_light + vec3(0.24, 0.34, 0.43) * edge;
		COLOR = lane;
	}
}
