// =============================================================================
// sprite.glsl — sokol-shdc annotated shader
//
// Compile with sokol-shdc:
//   sokol-shdc --input sprite.glsl --output sprite.glsl.h \
//              --slang glsl430:hlsl5:wgsl
//
// This single file produces shader code for:
//   - GLSL 4.3  (Vulkan via SPIR-V  / Linux)
//   - HLSL 5.0  (Direct3D 11        / Windows)
//   - WGSL      (WebGPU             / Web)
// =============================================================================

@vs vs

// Uniforms uploaded once per sprite draw call
layout(binding=0) uniform vs_params {
    mat4 mvp;           // orthographic projection * model matrix
    vec2 sprite_offset; // UV atlas top-left (use 0,0 for no atlas)
    vec2 sprite_size;   // UV atlas region size (use 1,1 for full texture)
};

// Per-vertex inputs (interleaved in one buffer)
in vec2 position; // local-space position [-0.5, 0.5]
in vec2 texcoord; // UV coordinate [0, 1]

// Outputs to the fragment shader
out vec2 v_uv;
out vec2 v_world_pos; // Used for lighting distance calculation

void main() {
    gl_Position = mvp * vec4(position, 0.0, 1.0);
    v_uv        = sprite_offset + texcoord * sprite_size;
    // Pass the world-space position so the FS can compute
    // distance to the light source correctly
    v_world_pos = (mvp * vec4(position, 0.0, 1.0)).xy;
}
@end

@fs fs

layout(binding=2) uniform texture2D sprite_tex;
layout(binding=1) uniform sampler sprite_smp;

// 2D point-light parameters
layout(binding=1) uniform fs_params {
    vec2 light_pos;     // light position in NDC space [-1, 1]
    float light_radius; // falloff radius in NDC units
    float _pad0;
    vec3 light_color;   // RGB color of the point light
    float _pad1;
    vec3 ambient;       // minimum ambient light color
    float _pad2;
};

in vec2 v_uv;
in vec2 v_world_pos;

out vec4 frag_color;

void main() {
    // Sample the sprite texture
    vec4 col = texture(sampler2D(sprite_tex, sprite_smp), v_uv);
    // Discard fully transparent fragments (hard cut-out alpha)
    if (col.a < 0.01) discard;

    // Simple 2D point light
    // Distance from this fragment to the light in NDC space
    float dist = length(v_world_pos - light_pos);

    // Quadratic (smooth) attenuation: 1 at distance 0, 0 at light_radius
    float att = clamp(1.0 - (dist / light_radius), 0.0, 1.0);
    att = att * att;

    // Final color = sprite_color * (ambient + attenuated point light)
    vec3 lighting = ambient + light_color * att;
    frag_color = vec4(col.rgb * lighting, col.a);
}

@end

// Bind the vs+fs pair under the name "sprite"
// sokol-shdc will generate: sprite_shader_desc(), ATTR_sprite_*, UB_*, IMG_*, SMP_*
@program sprite vs fs
