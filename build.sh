#!/bin/bash
set -eu
cd "$(dirname "$0")"

# --- Unpack Arguments --------------------------------------------------------
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"

for arg in "$@"; do declare "$arg=1"; done

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

if [ ! -f generated/sprite.glsl.h ]; then
  echo "ERROR: generated/sprite.glsl.h is missing. Run ./build_shader.sh first."
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

  cd ../..
  echo "[output] build/web/sokol_sprites.html"
  exit 0
fi

# --- Linux Build -------------------------------------------------------------
if [ -v clang ]; then
  compiler="${CC:-clang}"
  echo "[clang compile]"
elif [ -v gcc ]; then
  compiler="${CC:-gcc}"
  echo "[gcc compile]"
else
  compiler="${CC:-cc}"
  echo "[default compile: $compiler]"
fi

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

common="-std=c11 -I../../thirdparty -I../../src -I../../generated $vulkan_cflags $x11_cflags -DSOKOL_GLSL -DWIDTH=$WIDTH -DHEIGHT=$HEIGHT"
compile_debug="$compiler -g -O0 -D_DEBUG -DBUILD_DEBUG=1 $common"
compile_release="$compiler -O2 -DNDEBUG -DBUILD_DEBUG=0 $common"
compile="$compile_debug"
if [ -v release ]; then compile="$compile_release"; fi

link_flags="$vulkan_libs -ldl -lm -lpthread $x11_libs"

cd build/linux
echo "[building sokol_sprites]"
$compile ../../src/main.c $link_flags -o sokol_sprites

cd ../..
echo "[output] build/linux/sokol_sprites"
