// =============================================================================
// 2D sprite renderer with point-light shading
//
// Targets:
//   Windows : Direct3D 11   (define SOKOL_D3D11  at compile time)
//   Linux   : Vulkan        (define SOKOL_GLSL   at compile time — sokol uses
//                            SPIR-V internally; sokol-shdc compiles for you)
//   Web     : WebGPU        (define SOKOL_WGPU   at compile time + emcc)
//
// Build instructions are in CMakeLists.txt and the platform build scripts.
// =============================================================================

#define _POSIX_C_SOURCE 200809L

#define SOKOL_IMPL
#define SOKOL_LOG_IMPL

#if defined(_WIN32)
#define SOKOL_D3D11
#elif defined(__linux__)
#define SOKOL_VULKAN
#elif defined(__APPLE__)
#define SOKOL_METAL
#elif defined(__EMSCRIPTEN__)
#ifndef SOKOL_WGPU
#define SOKOL_WGPU
#endif
#else
#error "Unknown platform!"
#endif

#include "sokol/sokol_app.h"
#include "sokol/sokol_gfx.h"
#include "sokol/sokol_glue.h"
#include "sokol/sokol_log.h"

#include "sprite.glsl.h"
#include "typedef.h"

#include <math.h>
#include <string.h>

// Build a 2D orthographic projection matrix (matching GLSL/HLSL conventions)
// Maps [left,right] x [bottom,top] to [-1, 1] NDC.
fn mat4 mat4_ortho(float32 left, float32 right, float32 bottom, float32 top) {
    mat4 o  = {0};
    o.m[0]  = 2.0f / (right - left);
    o.m[5]  = 2.0f / (top - bottom);
    o.m[10] = -1.0f;
    o.m[12] = -(right + left) / (right - left);
    o.m[13] = -(top + bottom) / (top - bottom);
    o.m[15] = 1.0f;
    return o;
}

// TRS Matrix for a 2D sprite: translate(tx, ty) * scale (w,h)
fn mat4 mat4_trs2d(float32 tx, float32 ty, float32 width, float32 height) {
    mat4 t  = {0};
    t.m[0]  = width;
    t.m[5]  = height;
    t.m[10] = 1.0f;
    t.m[12] = tx;
    t.m[13] = ty;
    t.m[15] = 1.0f;
    return t;
}

// Standard column-major matrix multiplication (matching GLSL/HLSL conventions)
fn mat4 mat4_mul(mat4 a, mat4 b) {
    mat4 r = {0};
    for (int32 col = 0; col < 4; col++) {
        for (int32 row = 0; row < 4; row++) {
            float32 sum = 0.0f;
            for (int32 k = 0; k < 4; k++) {
                sum += a.m[k * 4 + row] * b.m[col * 4 + k];
            }
            r.m[col * 4 + row] = sum;
        }
    }
    return r;
}

// Sprite / Scene data

// A unit quad: x,y in [-0.5, 0.5], uv in [0, 1]
// Layout: position(float2) | texcoord(float2)
// clang-format off
static const float32 QUAD_VERTS[] = {
    -0.5f, -0.5f,  0.0f, 1.0f, // bottom-left
     0.5f, -0.5f,  1.0f, 1.0f, // bottom-right
     0.5f,  0.5f,  1.0f, 0.0f, // top-right
    -0.5f,  0.5f,  0.0f, 0.0f, // top-left
};

static const uint16 QUAD_INDICES[] = {
    0, 1, 2,
    0, 2, 3,
};
// clang-format on

#define TEX_W (128)
#define TEX_H (128)

static uint32 tex_data[TEX_W * TEX_H];

fn void build_texture(void) {
    for (int32 y = 0; y < TEX_H; y++) {
        for (int32 x = 0; x < TEX_W; x++) {
            float32 fx   = (x + 0.5f) / TEX_W - 0.5f; // [-0.5, 0.5]
            float32 fy   = (y + 0.5f) / TEX_H - 0.5f;
            float32 dist = sqrtf(fx * fx + fy * fy);

            // clang-format off
            uint8 r, g, b, a;
            if (dist < 0.45f) {
                if (dist > 0.35f) {
                    r = 255; g = 140; b = 0; a = 255; // Outer ring - orange
                }
                else {
                    r = 255; g = 230; b = 130; a = 255; // Inner circle - yellow-white
                }
                if (dist < 0.08f) {
                    r = 40; g = 30; b = 10; a = 255; // Small dark pupil/center
                }
            } else {
                r = 0; g = 0; b = 0; a = 0;
            }
            // clang-format on
            tex_data[y * TEX_W + x] = ((uint32)a << 24) | ((uint32)b << 16) |
                                      ((uint32)g << 8) | (uint32)r;
        }
    }
}

// How many sprites to draw
#define NUM_SPRITES (12)

typedef struct {
    float32 x, y;   // World Position (pixels from center)
    float32 vx, vy; // Velocity (pixels/second)
    float32 scale;  // Sprite size in pixels
    float32 spin;   // Rotation speed (unused in this simplified version)
} Sprite;

// Application state
static struct {
    // sokol-gfx resources
    sg_pipeline pipe;
    sg_bindings bind;
    sg_pass_action pass_action;
    // Background color (dark blue night)
    vec4 bg_color;
    // Sprite data
    Sprite sprites[NUM_SPRITES];
    // Elapsed time (seconds)
    float64 time;
    // Framebuffer size (updated every frame)
    int32 width, height;
} app;

fn void init(void) {
    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
        .logger.func = slog_func,
    });

    // Geometry buffers
    sg_buffer vbuf = sg_make_buffer(&(sg_buffer_desc){
        .usage.vertex_buffer = true,
        .data                = SG_RANGE(QUAD_VERTS),
        .label               = "quad-vb",
    });
    sg_buffer ibuf = sg_make_buffer(&(sg_buffer_desc){
        .usage.index_buffer = true,
        .data               = SG_RANGE(QUAD_INDICES),
        .label              = "quad-ib",
    });

    // Texture
    build_texture();
    sg_image img = sg_make_image(&(sg_image_desc){
        .width              = TEX_W,
        .height             = TEX_H,
        .data.mip_levels[0] = SG_RANGE(tex_data),
        .label              = "sprite-tex",
    });

    sg_sampler smp   = sg_make_sampler(&(sg_sampler_desc){
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
        .wrap_u     = SG_WRAP_CLAMP_TO_EDGE,
        .wrap_v     = SG_WRAP_CLAMP_TO_EDGE,
        .label      = "sprite-smp",
    });
    sg_view tex_view = sg_make_view(&(sg_view_desc){
        .texture.image = img,
        .label         = "sprite-tex-view",
    });

    // Pipeline
    // sprite_shader_desc() is generated by sokol-shdc; it picks the correct
    // shader bytecode for the active backend automatically
    sg_shader shd = sg_make_shader(sprite_shader_desc(sg_query_backend()));

    app.pipe = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = shd,
        .layout =
            {
                .attrs =
                    {
                        [ATTR_sprite_position] =
                            {.format = SG_VERTEXFORMAT_FLOAT2},
                        [ATTR_sprite_texcoord] =
                            {.format = SG_VERTEXFORMAT_FLOAT2},
                    },
            },
        .index_type = SG_INDEXTYPE_UINT16,
        // Alpha blending so transparent sprite edges look coorect
        .colors[0].blend =
            {
                .enabled          = true,
                .src_factor_rgb   = SG_BLENDFACTOR_SRC_ALPHA,
                .src_factor_alpha = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                .dst_factor_rgb   = SG_BLENDFACTOR_ONE,
                .dst_factor_alpha = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            },
        .label = "sprite-pip",
    });

    // Bindings
    // VIEW_sprite_tex / SMP_sprite_smp are generated by sokol-shdc
    app.bind = (sg_bindings){
        .vertex_buffers[0]        = vbuf,
        .index_buffer             = ibuf,
        .views[VIEW_sprite_tex]   = tex_view,
        .samplers[SMP_sprite_smp] = smp,
    };

    // Pass action (clear to dark background)
    app.pass_action = (sg_pass_action){
        .colors[0] = {
            .load_action = SG_LOADACTION_CLEAR,
            .clear_value = {0.04f, 0.04f, 0.10f, 1.0f},
        },
    };

    // Spawn sprites at random positions / velocities
    // (Using a simple deterministic pseudo-random for reproducibility)
    uint32 seed = 42;
    for (int32 i = 0; i < NUM_SPRITES; i++) {
// LGC random [-1, 1]
#define RAND()                                                                 \
    (seed = seed * 166452u + 1013904223u,                                      \
     ((float32)(seed >> 16) / 32767.5f) - 1.0f)

        float32 rx     = RAND() * 300.0f;
        float32 ry     = RAND() * 200.0f;
        float32 rvx    = RAND() * 80.0f;
        float32 rvy    = RAND() * 80.0f;
        float32 rscale = 50.0f + (RAND() + 1.0f) * 0.5f * 60.0f;

        app.sprites[i] = (Sprite){
            .x     = rx,
            .y     = ry,
            .vx    = rvx,
            .vy    = rvy,
            .scale = rscale,
        };
    }
}

fn void frame(void) {
    float64 dt  = sapp_frame_duration();
    app.time   += dt;
    app.width   = sapp_width();
    app.height  = sapp_height();

    float32 w = app.width;
    float32 h = app.height;

    // Orthographic projection: pixel-space, origin at center of screen
    mat4 proj = mat4_ortho(-w * 0.5f, w * 0.5f, -h * 0.5f, h * 0.5f);

    // Orbiting point light (NDC space, [-1, 1])
    float32 lx = cosf(app.time * 0.8f) * 0.55f;
    float32 ly = sinf(app.time * 1.1f) * 0.45f;

    // Fragment uniforms are the same for every sprite in this frame
    fs_params_t fsp = {
        .light_pos    = {lx, ly},
        .light_radius = 0.85f,                 // in NDC units
        .light_color  = {1.0f, 0.88f, 0.65f},  // warm white lantern
        .ambient      = {0.05f, 0.05f, 0.12f}, // cool blue shadow
    };

    sg_begin_pass(&(sg_pass){
        .action    = app.pass_action,
        .swapchain = sglue_swapchain(),
    });
    sg_apply_pipeline(app.pipe);
    sg_apply_bindings(&app.bind);

    // Draw each sprite
    for (int32 i = 0; i < NUM_SPRITES; i++) {
        Sprite* s = &app.sprites[i];

        // Bounce off the edges of a virtual play area
        float32 half_w = w * 0.5f - s->scale * 0.5f;
        float32 half_h = h * 0.5f - s->scale * 0.5f;

        s->x += s->vx * dt;
        s->y += s->vy * dt;

        if (s->x > half_w) {
            s->x  = half_w;
            s->vx = -fabsf(s->vx);
        }
        if (s->x < -half_w) {
            s->x  = -half_w;
            s->vx = fabsf(s->vx);
        }
        if (s->y > half_h) {
            s->y  = half_h;
            s->vy = -fabsf(s->vy);
        }
        if (s->y < -half_h) {
            s->y  = -half_h;
            s->vy = fabsf(s->vy);
        }

        // Build MVP = proj * model(translate, scale)
        mat4 model = mat4_trs2d(s->x, s->y, s->scale, s->scale);
        mat4 mvp   = mat4_mul(proj, model);

        // Copy MVP into the generated uniform struct
        vs_params_t vsp;
        memcpy(vsp.mvp, mvp.m, sizeof(float32) * 16);
        vsp.sprite_offset[0] = 0.0f; // Full texture (no atlas)
        vsp.sprite_offset[1] = 0.0f;
        vsp.sprite_size[0]   = 1.0f;
        vsp.sprite_size[1]   = 1.0f;

        // UB_vs_params / UB_fs_params are generated constants from sokol-shdc
        sg_apply_uniforms(UB_vs_params, &SG_RANGE(vsp));
        sg_apply_uniforms(UB_fs_params, &SG_RANGE(fsp));

        sg_draw(0, 6, 1); // 6 indices = 2 triangles = 1 quad
    }

    sg_end_pass();
    sg_commit();
}

fn void cleanup(void) {
    sg_shutdown();
}

sapp_desc sokol_main(int argc, char* argv[]) {
    (void)argc;
    (void)argv;

    return (sapp_desc){
        .init_cb      = init,
        .frame_cb     = frame,
        .cleanup_cb   = cleanup,
        .width        = APP_WIDTH,
        .height       = APP_HEIGHT,
        .window_title = "SOKOL EXAMPLE 2D SPRITES + POINT LIGHT",
        .logger.func  = slog_func,
    };
}
