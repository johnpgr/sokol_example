#!/bin/bash
set -eu
cd "$(dirname "$0")"

# --- Unpack Arguments --------------------------------------------------------
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"

for arg in "$@"; do declare "$arg=1"; done

want_compile_db=0
if [ -v compile_commands ] || [ -v compdb ] || [ -v ccdb ]; then
  want_compile_db=1
fi

want_shader_build=0
if [ -v shaders ] || [ -v shader ] || [ -v shdc ]; then
  want_shader_build=1
fi

generate_compile_db() {
  target_dir="$1"
  compile_cmd="$2"
  src_abs="$(cd src && pwd)/main.c"
  out_dir="$(cd "$target_dir" && pwd)"

  cat > compile_commands.json <<EOF
[
{"directory":"$out_dir","command":"$compile_cmd -c $src_abs","file":"$src_abs"}
]
EOF

  # Keep a single compile database at repo root.
  rm -f "$target_dir/compile_commands.json"
}

if [ -v clean ]; then
  rm -rf build
  echo "[cleaned build directory]"
  exit 0
fi

if [ ! -v linux ] && [ ! -v web ]; then linux=1; fi
if [ ! -v release ]; then debug=1; fi

if [ -v debug ]; then echo "[debug mode]"; fi
if [ -v release ]; then echo "[release mode]"; fi
if [ -v linux ]; then echo "[linux target]"; fi
if [ -v web ]; then echo "[web target]"; fi

# --- Prep Directories --------------------------------------------------------
mkdir -p build
mkdir -p generated

# --- Shader Generation -------------------------------------------------------
shdc=''
os_name="$(uname -s)"
arch_name="$(uname -m)"

if [ "$os_name" = "Linux" ]; then
  if [ "$arch_name" = "aarch64" ] || [ "$arch_name" = "arm64" ]; then
    shdc="./thirdparty/tools/sokol-shdc/bin/linux_arm64/sokol-shdc"
  else
    shdc="./thirdparty/tools/sokol-shdc/bin/linux/sokol-shdc"
  fi
elif [ "$os_name" = "Darwin" ]; then
  if [ "$arch_name" = "arm64" ]; then
    shdc="./thirdparty/tools/sokol-shdc/bin/osx_arm64/sokol-shdc"
  else
    shdc="./thirdparty/tools/sokol-shdc/bin/osx/sokol-shdc"
  fi
fi

if [ ! -x "$shdc" ]; then
  shdc=''
fi

if [ -f shaders/sprite.glsl ]; then
  if [ -n "$shdc" ]; then
    if [ "$want_shader_build" = "1" ]; then
      echo "[compiling shaders]"
      "$shdc" --input "$PWD/shaders/sprite.glsl" --output "$PWD/generated/sprite.glsl.h" --slang glsl430:hlsl5:wgsl:spirv_vk
    elif [ ! -f generated/sprite.glsl.h ]; then
      echo "[generated shader missing, compiling]"
      "$shdc" --input "$PWD/shaders/sprite.glsl" --output "$PWD/generated/sprite.glsl.h" --slang glsl430:hlsl5:wgsl:spirv_vk
    else
      echo "[shader generation skipped; pass shaders to enable]"
    fi
  elif [ ! -f generated/sprite.glsl.h ]; then
    echo "ERROR: sokol-shdc not found and generated/sprite.glsl.h is missing."
    exit 1
  else
    echo "[warning] sokol-shdc not found, using existing generated/sprite.glsl.h"
  fi
elif [ ! -f generated/sprite.glsl.h ]; then
  echo "ERROR: shaders/sprite.glsl and generated/sprite.glsl.h are both missing."
  exit 1
fi

# --- Web Build ---------------------------------------------------------------
if [ -v web ]; then
  if [ -f "thirdparty/tools/emsdk/emsdk_env.sh" ]; then
    if [ ! -d "thirdparty/tools/emsdk/upstream/emscripten" ]; then
      echo "[installing emsdk]"
      "thirdparty/tools/emsdk/emsdk" install latest
      "thirdparty/tools/emsdk/emsdk" activate latest
    fi
    source "thirdparty/tools/emsdk/emsdk_env.sh"
  fi

  compiler="${EMCC:-emcc}"
  mkdir -p build/web

  if [ ! -f web/shell.html ]; then
    echo "ERROR: web/shell.html is missing."
    exit 1
  fi

  common="-std=c11 -I../../thirdparty -I../../src -I../../generated -DSOKOL_WGPU --use-port=emdawnwebgpu -DWIDTH=$WIDTH -DHEIGHT=$HEIGHT"
  compile_debug="$compiler -g -O0 -D_DEBUG -DBUILD_DEBUG=1 $common"
  compile_release="$compiler -O2 -DNDEBUG -DBUILD_DEBUG=0 $common"
  compile="$compile_debug"
  if [ -v release ]; then compile="$compile_release"; fi

  link_flags="-sASYNCIFY -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=web --shell-file shell.html"

  cd build/web
  echo "[building sokol_sprites.html]"
  sed -e "s/{{WIDTH}}/$WIDTH/g" -e "s/{{HEIGHT}}/$HEIGHT/g" ../../web/shell.html > shell.html
  $compile ../../src/main.c $link_flags -o sokol_sprites.html
  if [ "$want_compile_db" = "1" ]; then
    echo "[generating compile_commands.json]"
    cd ../..
    generate_compile_db "build/web" "$compile"
  else
    echo "[compile_commands generation skipped; pass compdb to enable]"
    cd ../..
  fi
  echo "[output] build/web/sokol_sprites.html"
  if [ "$want_compile_db" = "1" ]; then
    echo "[output] compile_commands.json"
  fi
  exit 0
fi

# --- Linux Build -------------------------------------------------------------
compiler="${CC:-clang}"
echo "[clang compile: $compiler]"

vulkan_cflags=''
vulkan_libs='-lvulkan'
x11_cflags=''
x11_libs='-lX11 -lXi -lXcursor'

if command -v pkg-config >/dev/null 2>&1; then
  if pkg-config --exists vulkan; then
    vulkan_cflags="$(pkg-config --cflags vulkan)"
    vulkan_libs="$(pkg-config --libs vulkan)"
  fi
  if pkg-config --exists x11 xi xcursor; then
    x11_cflags="$(pkg-config --cflags x11 xi xcursor)"
    x11_libs="$(pkg-config --libs x11 xi xcursor)"
  fi
fi

mkdir -p build/linux

common="-std=c11 -D_POSIX_C_SOURCE=200809L -I../../thirdparty -I../../src -I../../generated $vulkan_cflags $x11_cflags -DSOKOL_VULKAN -DWIDTH=$WIDTH -DHEIGHT=$HEIGHT"
compile_debug="$compiler -g -O0 -D_DEBUG -DBUILD_DEBUG=1 $common"
compile_release="$compiler -O2 -DNDEBUG -DBUILD_DEBUG=0 $common"
compile="$compile_debug"
if [ -v release ]; then compile="$compile_release"; fi

link_flags="$vulkan_libs -ldl -lm -lpthread $x11_libs"

cd build/linux
echo "[building sokol_sprites]"
$compile ../../src/main.c $link_flags -o sokol_sprites
if [ "$want_compile_db" = "1" ]; then
  echo "[generating compile_commands.json]"
  cd ../..
  generate_compile_db "build/linux" "$compile"
else
  echo "[compile_commands generation skipped; pass compdb to enable]"
  cd ../..
fi
echo "[output] build/linux/sokol_sprites"
if [ "$want_compile_db" = "1" ]; then
  echo "[output] compile_commands.json"
fi
