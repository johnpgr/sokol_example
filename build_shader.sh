#!/bin/bash
set -eu
cd "$(dirname "$0")"

mkdir -p generated

if [ ! -f shaders/sprite.glsl ]; then
  echo "ERROR: shaders/sprite.glsl is missing."
  exit 1
fi

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
  echo "ERROR: sokol-shdc not found for this platform."
  exit 1
fi

echo "[compiling shaders]"
"$shdc" --input "$PWD/shaders/sprite.glsl" --output "$PWD/generated/sprite.glsl.h" --slang glsl430:hlsl5:wgsl:spirv_vk

echo "[output] generated/sprite.glsl.h"
