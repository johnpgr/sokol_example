#pragma once

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;
typedef int8_t int8;
typedef int16_t int16;
typedef int32_t int32;
typedef int64_t int64;
typedef float float32;
typedef double float64;

#define fn static

// ============================= MATH TYPES ====================================
// Minimal 2D/3D/4D vector types (matching GLSL/HLSL conventions)
typedef union {
    struct { float32 x, y; };
    float32 v[2];
} vec2;

typedef union {
    struct { float32 x, y, z; };
    float32 v[3];
} vec3;

typedef union {
    struct { float32 x, y, z, w; };
    float32 v[4];
} vec4;

// Minimal 4x4 float matrix (column-major, matching GLSL/HLSL conventions)
typedef union {
    struct { vec4 x, y, z, w; };
    float32 m[16];
} mat4;
