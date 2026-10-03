shader_type canvas_item;
render_mode unshaded;

uniform vec4 cream : source_color = vec4(0.97, 0.91, 0.80, 1.0);
uniform vec4 shadow : source_color = vec4(0.42, 0.44, 0.42, 1.0);
uniform vec4 brass : source_color = vec4(0.86, 0.66, 0.34, 1.0);
uniform vec4 accent : source_color = vec4(0.39, 0.74, 0.73, 1.0);
varying vec4 authored_color;

void vertex() {
	authored_color = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// White-modulated artwork receives the grade. Primitive colors, warning
	// rings and labels retain their explicitly authored gameplay contrast.
	float image_draw = step(0.995, min(authored_color.r, min(authored_color.g, authored_color.b)));
	float light = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float value = smoothstep(0.0, 0.93, pow(max(light, 0.0), 0.76));
	vec3 neutral = mix(shadow.rgb, cream.rgb, value);
	float warm = smoothstep(0.045, 0.22, source.r - source.b);
	vec3 gold = mix(shadow.rgb * 0.84, brass.rgb, value);
	float cool = smoothstep(0.025, 0.20, max(source.g, source.b) - source.r);
	vec3 colored = mix(neutral, gold, warm * 0.78);
	colored = mix(colored, mix(shadow.rgb * 0.82, accent.rgb, value), cool * 0.86);
	COLOR = vec4(mix(source.rgb, colored, image_draw), source.a) * authored_color;
}
