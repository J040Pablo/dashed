shader_type canvas_item;

uniform float scan_strength : hint_range(0.0, 1.0) = 0.25;
uniform float scan_density : hint_range(50.0, 800.0) = 240.0;
uniform vec4 tint : hint_color = vec4(1.0, 0.4, 0.9, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float line = sin((UV.y * float(SCREEN_PIXEL_SIZE.y) * scan_density) * 3.14159);
    float factor = smoothstep(-0.6, 0.6, line) * scan_strength;
    vec3 col = mix(tex.rgb, tex.rgb * (1.0 - factor), factor);
    // subtle tint
    col = mix(col, tint.rgb, 0.05 * scan_strength);
    COLOR = vec4(col, tex.a);
}
