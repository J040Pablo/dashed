shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_speed : hint_range(0.0, 8.0) = 1.0;

void fragment(){
    vec2 uv = UV;
    float t = TIME * time_speed;
    // horizontal jitter
    float h_offset = sin(uv.y * 50.0 + t * 6.0) * 0.01 * intensity;
    // slice offset
    float slice = step(0.95, fract(sin(t * 7.0) * 43758.5453));
    uv.x += h_offset * slice;
    // color separation
    vec4 c = texture(TEXTURE, uv);
    vec2 sep_uv = uv;
    sep_uv.x += 0.002 * intensity;
    float r = texture(TEXTURE, sep_uv).r;
    sep_uv.x -= 0.004 * intensity;
    float b = texture(TEXTURE, sep_uv).b;
    vec3 outcol = vec3(r, c.g, b);
    // apply vignette-ish darkening when glitching
    float vign = 1.0 - intensity * 0.2;
    outcol *= vign;
    COLOR = vec4(outcol, c.a);
}
