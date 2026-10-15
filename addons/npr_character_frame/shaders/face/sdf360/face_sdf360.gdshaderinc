// Original directional SDF atlas. Linear data, no mip cross-tile bleeding.
uniform bool u_npr_sdf360_enabled = false;
uniform sampler2D u_npr_sdf360_atlas : filter_linear, repeat_disable;
uniform float u_npr_sdf360_softness : hint_range(0.002, 0.15) = 0.025;
uniform bool u_npr_sdf360_debug = false;
varying vec3 v_npr_sdf360_light;
float npr_sdf360_sample(vec2 uv, float yaw_index, float elevation_index) {
    vec2 tile = vec2(mod(yaw_index, 24.0), clamp(elevation_index, 0.0, 6.0));
    vec2 atlas_size = vec2(textureSize(u_npr_sdf360_atlas, 0));
    vec2 tile_size = atlas_size / vec2(24.0, 7.0);
    vec2 pixel = tile * tile_size + vec2(2.5) + clamp(uv, vec2(0.0), vec2(1.0)) * (tile_size - vec2(5.0));
    return texture(u_npr_sdf360_atlas, pixel / atlas_size).r;
}
float npr_sdf360_factor(vec2 uv, vec3 direction) {
    vec3 l = direction / max(length(direction), 0.00001);
    float yaw = mod(atan(l.x, l.z) / TAU + 1.0, 1.0) * 24.0;
    float elevation = (asin(clamp(l.y, -1.0, 1.0)) / PI + 0.5) * 6.0;
    vec2 index = floor(vec2(yaw, elevation));
    vec2 t = fract(vec2(yaw, elevation));
    float a = mix(npr_sdf360_sample(uv, index.x, index.y), npr_sdf360_sample(uv, index.x+1.0, index.y), t.x);
    float b = mix(npr_sdf360_sample(uv, index.x, index.y+1.0), npr_sdf360_sample(uv, index.x+1.0, index.y+1.0), t.x);
    return smoothstep(0.5-u_npr_sdf360_softness, 0.5+u_npr_sdf360_softness, mix(a,b,t.y));
}
