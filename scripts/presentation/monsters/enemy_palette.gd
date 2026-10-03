extends RefCounted
## Painted adventure palettes share one shader, while each body owns its
## uniforms. Source alpha, texture regions and foot registration stay intact.

const FAMILIES: Dictionary = {
	"coral": {"outline":"302739", "shade":"994b55", "primary":"e78369", "highlight":"ffc593", "energy":"82e3dc", "trim":"e5ae58"},
	"indigo": {"outline":"282943", "shade":"4a539b", "primary":"798bea", "highlight":"b5cbfa", "energy":"80e9ee", "trim":"dfb36b"},
	"jade": {"outline":"253d3d", "shade":"377f78", "primary":"62c2a6", "highlight":"b1e3bf", "energy":"d8ef8d", "trim":"e0b965"},
	"heavy": {"outline":"342b3c", "shade":"9c5a4d", "primary":"e7a16a", "highlight":"ffd6a2", "energy":"83dbdd", "trim":"f1c66c"},
	"orchid": {"outline":"342846", "shade":"78529b", "primary":"b68bd6", "highlight":"e0bbee", "energy":"a4e6ef", "trim":"e6b578"},
}

# Explicit coverage also handles legacy catalog profiles and preview actors
# that do not pass through EnemyProfiles.resolve(). Ranged skirmishers retain
# the cool ranged palette instead of inheriting the generic melee palette.
const IDENTITIES: Dictionary = {
	"M01":"coral", "M02":"coral", "M03":"indigo", "M04":"coral", "M05":"coral", "M06":"jade",
	"M07":"coral", "M08":"heavy", "M09":"jade", "M10":"orchid", "M11":"indigo", "M12":"jade",
	"M13":"orchid", "M14":"coral", "M15":"orchid", "M16":"jade", "M17":"jade", "M18":"heavy",
	"M19":"jade", "M20":"indigo", "M21":"orchid", "M22":"indigo", "M23":"coral", "M24":"indigo",
	"M25":"heavy", "M26":"heavy", "M27":"coral", "M28":"orchid", "M29":"orchid", "M30":"jade",
	"M31":"indigo", "M32":"orchid", "M33":"jade", "M34":"heavy", "M35":"jade", "M36":"indigo",
	"BO01":"heavy", "BO02":"jade", "BO03":"indigo", "BO04":"orchid",
}

const SHADER_CODE := """
shader_type canvas_item;
uniform vec4 palette_outline : source_color;
uniform vec4 palette_shade : source_color;
uniform vec4 palette_primary : source_color;
uniform vec4 palette_highlight : source_color;
uniform vec4 palette_energy : source_color;
uniform vec4 palette_trim : source_color;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.94;
uniform float trim_strength : hint_range(0.0, 1.0) = 0.92;
uniform float impact_mix : hint_range(0.0, 1.0) = 0.0;
uniform bool preserve_source_color = false;
uniform bool textured_body = true;
varying vec4 body_modulate;

void vertex() {
	// Preserve actor/status tint and stealth/corpse alpha after palette mapping.
	body_modulate = COLOR;
}

void fragment() {
	if (!textured_body) {
		// Missing-art primitives are painted on the CPU. Preserve the same
		// contact flash as textured bodies without treating white as a sprite.
		COLOR.rgb = mix(COLOR.rgb, vec3(1.0, 0.965, 0.87), impact_mix);
	} else {
	vec4 source = texture(TEXTURE, UV);
	vec3 rgb = source.rgb;
	float luminance = dot(rgb, vec3(0.299, 0.587, 0.114));
	float maximum = max(rgb.r, max(rgb.g, rgb.b));
	float minimum = min(rgb.r, min(rgb.g, rgb.b));
	float saturation = (maximum - minimum) / max(maximum, 0.001);
	float warm = smoothstep(0.015, 0.12, rgb.r - rgb.b);
	float neutral = 1.0 - smoothstep(0.30, 0.65, saturation);
	// A tonal ramp lifts the old coal materials, keeping very dark engraved
	// seams and silhouettes. It is not multiplication by a bright tint.
	vec3 paint = mix(palette_outline.rgb, palette_shade.rgb, smoothstep(0.025, 0.19, luminance));
	paint = mix(paint, palette_primary.rgb, smoothstep(0.13, 0.48, luminance));
	paint = mix(paint, palette_highlight.rgb, smoothstep(0.48, 0.82, luminance));
	paint = mix(paint, vec3(0.98, 0.94, 0.84), smoothstep(0.84, 1.0, luminance));
	// Neutral steel becomes enamel; warm metal remains brass trim. Cool
	// authored lenses/crystals keep a separate energy accent and their detail.
	float brass = warm * smoothstep(0.20, 0.43, saturation) * smoothstep(0.055, 0.18, luminance);
	brass *= 1.0 - smoothstep(0.78, 0.96, luminance);
	vec3 trim = mix(vec3(0.25, 0.16, 0.16), palette_trim.rgb, smoothstep(0.055, 0.47, luminance));
	trim = mix(trim, vec3(0.98, 0.85, 0.59), smoothstep(0.52, 0.84, luminance));
	paint = mix(paint, trim, brass * trim_strength);
	float cool_energy = (1.0 - warm) * smoothstep(0.24, 0.58, saturation) * smoothstep(0.18, 0.53, luminance);
	float hot_lens = warm * smoothstep(0.73, 0.95, saturation) * smoothstep(0.32, 0.64, luminance);
	float energy = max(cool_energy, hot_lens);
	paint = mix(paint, palette_energy.rgb * (0.52 + luminance * 0.56), energy * 0.90);
	float material_mask = max(0.82, max(neutral, warm));
	// New painted families already own their material colors. Keep every
	// authored hue; only the same brief confirmed-contact flash remains active.
	vec3 colored = preserve_source_color ? rgb : mix(rgb, paint, material_mask * palette_mix);
	colored = mix(colored, vec3(1.0, 0.965, 0.87), impact_mix);
	COLOR = vec4(colored, source.a) * body_modulate;
	}
}
"""

static var _shader: Shader

static func family_for(identity: String, profile: Dictionary = {}) -> String:
	var explicit: String = str(profile.get("visual_palette", ""))
	if FAMILIES.has(explicit):
		return explicit
	if IDENTITIES.has(identity):
		return str(IDENTITIES[identity])
	var role: String = str(profile.get("archetype", "skirmisher"))
	if str(profile.get("role", "")) in ["ranged", "artillery", "bomber"]:
		return "indigo"
	return str({"tank":"heavy", "caster":"indigo", "support":"jade", "assassin":"orchid"}.get(role, "coral"))

static func material_for(identity: String, profile: Dictionary = {}, full_color: bool = false) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var result := ShaderMaterial.new()
	result.shader = _shader
	var palette: Dictionary = colors_for(identity, profile)
	for key: String in palette:
		result.set_shader_parameter("palette_" + key, palette[key])
	result.set_shader_parameter("palette_mix", 0.0 if full_color else 0.94)
	result.set_shader_parameter("preserve_source_color", full_color)
	var organic: bool = identity in ["M04", "M10", "M11", "M12", "M13", "M14", "M15", "M16", "M17", "M18", "M28", "M29", "M32", "M33", "M35", "BO02"]
	# Organic highlights keep some warm bark/chitin; mechanical joints retain
	# their stronger brass identity beside the new enamel armor colors.
	result.set_shader_parameter("trim_strength", 0.53 if organic else 0.92)
	result.set_shader_parameter("impact_mix", 0.0)
	return result

static func colors_for(identity: String, profile: Dictionary = {}) -> Dictionary:
	var palette: Dictionary = FAMILIES[family_for(identity, profile)]
	var result: Dictionary = {}
	# Small deterministic variations keep a family coherent across its enemies.
	# Bosses use the full authored family rather than a random hue.
	var variant: float = float((identity.hash() & 0x7fffffff) % 5 - 2) * 0.009 if not identity.begins_with("BO") else 0.0
	for key: String in palette:
		var color: Color = Color(str(palette[key]))
		if key in ["shade", "primary", "highlight"]:
			color = Color.from_hsv(fposmod(color.h + variant, 1.0), color.s, color.v, color.a)
		result[key] = color
	return result
