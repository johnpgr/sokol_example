@REM @echo off
setlocal
cd /D "%~dp0"

if not exist generated mkdir generated

if not exist "%~dp0shaders\sprite.glsl" (
  echo ERROR: shaders\sprite.glsl is missing.
  exit /b 1
)

set "shdc=%~dp0thirdparty\tools\sokol-shdc\bin\win32\sokol-shdc.exe"
if not exist "%shdc%" (
  echo ERROR: sokol-shdc not found at thirdparty\tools\sokol-shdc\bin\win32\sokol-shdc.exe
  exit /b 1
)

echo [compiling shaders]
"%shdc%" --input "%~dp0shaders\sprite.glsl" --output "%~dp0generated\sprite.glsl.h" --slang glsl430:hlsl5:wgsl || exit /b 1

echo [output] generated\sprite.glsl.h
