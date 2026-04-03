@echo off
setlocal enabledelayedexpansion
cd /D "%~dp0"

:: --- Unpack Arguments -------------------------------------------------------
if not defined WIDTH set WIDTH=1280
if not defined HEIGHT set HEIGHT=720

for %%a in (%*) do set "%%~a=1"

if "%clean%"=="1" (
  if exist build rmdir /S /Q build
  echo [cleaned build directory]
  exit /b 0
)

if not "%windows%"=="1" if not "%web%"=="1" set windows=1

if not "%release%"=="1" set debug=1
if "%debug%"=="1" (
  set release=0
  echo [debug mode]
)
if "%release%"=="1" (
  set debug=0
  echo [release mode]
)
if "%windows%"=="1" echo [windows target]
if "%web%"=="1" echo [web target]

:: --- Prep Directories -------------------------------------------------------
if not exist build mkdir build
if not exist generated mkdir generated

if not exist "%~dp0generated\sprite.glsl.h" (
  echo ERROR: generated\sprite.glsl.h is missing. Run build_shader.bat first.
  exit /b 1
)

:: --- Web Build ---------------------------------------------------------------
if "%web%"=="1" (
  if exist "%~dp0thirdparty\tools\emsdk\emsdk_env.bat" (
    if not exist "%~dp0thirdparty\tools\emsdk\upstream\emscripten" (
      echo [installing emsdk]
      call "%~dp0thirdparty\tools\emsdk\emsdk.bat" install latest
      call "%~dp0thirdparty\tools\emsdk\emsdk.bat" activate latest
    )
    call "%~dp0thirdparty\tools\emsdk\emsdk_env.bat" >nul 2>&1
  )

  if not exist build\web mkdir build\web
  if not exist "%~dp0web\shell.html" (
    echo ERROR: web\shell.html is missing.
    exit /b 1
  )

  setlocal enabledelayedexpansion
  set "compiler=emcc"
  if defined EMCC set "compiler=!EMCC!"
  set common=-std=c11 -I..\..\thirdparty -I..\..\src -I..\..\generated -DSOKOL_WGPU --use-port=emdawnwebgpu -DWIDTH=%WIDTH% -DHEIGHT=%HEIGHT%
  set "compile_debug=!compiler! -g -O0 -D_DEBUG -DBUILD_DEBUG=1 !common!"
  set "compile_release=!compiler! -O2 -DNDEBUG -DBUILD_DEBUG=0 !common!"

  if "%debug%"=="1" set "compile=!compile_debug!"
  if "%release%"=="1" set "compile=!compile_release!"

  pushd build\web
  echo [building sokol_sprites.html]
  powershell -Command "(Get-Content ..\..\web\shell.html) -replace '{{WIDTH}}', '%WIDTH%' -replace '{{HEIGHT}}', '%HEIGHT%' | Set-Content shell.html"
  !compile! ..\..\src\main.c -sASYNCIFY -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=web --shell-file shell.html -o sokol_sprites.html || exit /b 1
  popd

  if not exist "%~dp0build\web\sokol_sprites.html" (
    echo ERROR: emcc completed but build\web\sokol_sprites.html was not produced.
    exit /b 1
  )
  endlocal

  echo [output] build\web\sokol_sprites.html
  exit /b 0
)

:: --- Windows Build -----------------------------------------------------------
if not exist build\windows mkdir build\windows

set common=/nologo /std:c11 /FC /I..\..\thirdparty /I..\..\src /I..\..\generated /DSOKOL_D3D11 /DWIDTH=%WIDTH% /DHEIGHT=%HEIGHT%
set cflags_debug=/Zi /Od /D_DEBUG /DBUILD_DEBUG=1 %common%
set cflags_release=/O2 /DNDEBUG /DBUILD_DEBUG=0 %common%

if "%debug%"=="1" set cflags=%cflags_debug%
if "%release%"=="1" set cflags=%cflags_release%
set compile=cl %cflags%

pushd build\windows
echo [building sokol_sprites.exe]
%compile% ..\..\src\main.c /link /OUT:sokol_sprites.exe d3d11.lib dxgi.lib dxguid.lib kernel32.lib user32.lib gdi32.lib ole32.lib || exit /b 1
popd

echo [output] build\windows\sokol_sprites.exe
