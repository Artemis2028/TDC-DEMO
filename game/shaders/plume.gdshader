// Exhaust glow in vacuum: no flame, just a faint emissive plasma volume. Additive, so it only ever brightens.
// UV.y runs from 0 at the nozzle to 1 at the far end. Brightness falls along the plume (ramp after the Dagger v4
// exhaust concept) and toward the plume's silhouette, so the enclosing mesh never shows a hard edge.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.24, 0.40, 1.0, 1.0);
uniform float strength = 1.0;

float ramp(float t) {
	// (position, value): (0, .3) (.06, 1) (.22, .75) (.6, .22) (.88, .025) (1, 0), eased between points
	if (t < 0.06) return mix(0.3, 1.0, smoothstep(0.0, 0.06, t));
	if (t < 0.22) return mix(1.0, 0.75, smoothstep(0.06, 0.22, t));
	if (t < 0.6) return mix(0.75, 0.22, smoothstep(0.22, 0.6, t));
	if (t < 0.88) return mix(0.22, 0.025, smoothstep(0.6, 0.88, t));
	return mix(0.025, 0.0, smoothstep(0.88, 1.0, t));
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = facing * facing;
	ALBEDO = tint.rgb * strength * ramp(UV.y) * soft;
}
