@echo off
setlocal enabledelayedexpansion
cd /D "%~dp0"

:: --- Unpack Arguments -------------------------------------------------------
if not defined WIDTH set WIDTH=1280
if not defined HEIGHT set HEIGHT=720

for %%a in (%*) do set "%%~a=1"

set "want_compile_db=0"
if "%compile_commands%"=="1" set "want_compile_db=1"
if "%compdb%"=="1" set "want_compile_db=1"
if "%ccdb%"=="1" set "want_compile_db=1"

set "want_shader_build=0"
if "%shaders%"=="1" set "want_shader_build=1"
if "%shader%"=="1" set "want_shader_build=1"
if "%shdc%"=="1" set "want_shader_build=1"

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

:: --- Shader Generation ------------------------------------------------------
set "shdc="
if exist "%~dp0thirdparty\tools\sokol-shdc\bin\win32\sokol-shdc.exe" set "shdc=%~dp0thirdparty\tools\sokol-shdc\bin\win32\sokol-shdc.exe"

if exist "%~dp0shaders\sprite.glsl" (
  if defined shdc (
    if "%want_shader_build%"=="1" (
      echo [compiling shaders]
      "%shdc%" --input "%~dp0shaders\sprite.glsl" --output "%~dp0generated\sprite.glsl.h" --slang glsl430:hlsl5:wgsl || exit /b 1
    ) else (
      if not exist "%~dp0generated\sprite.glsl.h" (
        echo [generated shader missing, compiling]
        "%shdc%" --input "%~dp0shaders\sprite.glsl" --output "%~dp0generated\sprite.glsl.h" --slang glsl430:hlsl5:wgsl || exit /b 1
      ) else (
        echo [shader generation skipped; pass shaders to enable]
      )
    )
  ) else (
    if not exist "%~dp0generated\sprite.glsl.h" (
      echo ERROR: sokol-shdc not found and generated\sprite.glsl.h is missing.
      exit /b 1
    )
    echo [warning] sokol-shdc not found, using existing generated\sprite.glsl.h
  )
) else (
  if not exist "%~dp0generated\sprite.glsl.h" (
    echo ERROR: shaders\sprite.glsl and generated\sprite.glsl.h are both missing.
    exit /b 1
  )
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

  if "!want_compile_db!"=="1" (
    echo [generating compile_commands.json]
    set "compile_db_command=!compile! -c ..\..\src\main.c"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $entry=[ordered]@{ directory=(Get-Location).Path; command=$env:compile_db_command; file=(Resolve-Path '..\..\src\main.c').Path }; $json='[' + (ConvertTo-Json -InputObject $entry -Depth 4 -Compress) + ']'; Set-Content -Encoding utf8 -Path 'compile_commands.json' -Value $json" || exit /b 1
    copy /Y compile_commands.json ..\..\compile_commands.json >nul || exit /b 1
  ) else (
    echo [compile_commands generation skipped; pass compdb to enable]
  )
  popd

  if not exist "%~dp0build\web\sokol_sprites.html" (
    echo ERROR: emcc completed but build\web\sokol_sprites.html was not produced.
    exit /b 1
  )
  endlocal

  echo [output] build\web\sokol_sprites.html
  if "%want_compile_db%"=="1" echo [output] build\web\compile_commands.json
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
if "%want_compile_db%"=="1" (
  set "compile_db_stamp=compile_commands.stamp"
  set "regen_compile_db=1"

  if exist compile_commands.json if exist "%compile_db_stamp%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $db='compile_commands.json'; $stamp='compile_commands.stamp'; $srcRoot=Resolve-Path '..\..\src'; $dbTime=(Get-Item $db).LastWriteTimeUtc; $srcNewer=Get-ChildItem -Path $srcRoot -Filter '*.c' -File | Where-Object { $_.LastWriteTimeUtc -gt $dbTime } | Select-Object -First 1; if ($env:INCLUDE) { $inc=$env:INCLUDE } else { $inc='' }; $fingerprint=('cflags=' + $env:cflags + [Environment]::NewLine + 'include=' + $inc).TrimEnd([char]13,[char]10); $old=(Get-Content $stamp -Raw).TrimEnd([char]13,[char]10); if (($null -eq $srcNewer) -and ($old -eq $fingerprint)) { exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 set "regen_compile_db=0"
  )

  if "%regen_compile_db%"=="0" (
    if not exist ..\..\compile_commands.json copy /Y compile_commands.json ..\..\compile_commands.json >nul || exit /b 1
    echo [compile_commands.json up to date]
  ) else (
    echo [generating compile_commands.json]
    where clang-cl >nul 2>&1
    if errorlevel 1 (
      echo [warning] clang-cl not found on PATH, skipping compile_commands.json generation
    ) else (
      del /Q *.ccdb.json >nul 2>&1
      for %%F in (..\..\src\*.c) do (
        clang-cl /nologo /c %%F %cflags% /clang:-MJ /clang:%%~nxF.ccdb.json || exit /b 1
      )
      powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $includeDirs=@(); if ($env:INCLUDE) { $includeDirs=@($env:INCLUDE -split ';' | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique) }; $rows=@(Get-ChildItem -Filter '*.ccdb.json' -File | Sort-Object Name | ForEach-Object { $raw=(Get-Content $_.FullName -Raw).Trim(); if ($raw.EndsWith(',')) { $raw=$raw.Substring(0, $raw.Length-1) }; $obj=$raw | ConvertFrom-Json; if ($obj.file -and -not [System.IO.Path]::IsPathRooted([string]$obj.file)) { $obj.file=[System.IO.Path]::GetFullPath((Join-Path $obj.directory ([string]$obj.file))) }; if ($obj.arguments) { $args=@($obj.arguments | Where-Object { $_ -ne '/clang:-MJ' -and ($_ -notmatch '^/clang:') }); foreach ($inc in $includeDirs) { $args += ('/imsvc' + $inc) }; $obj.arguments=$args }; $obj }); if ($rows.Count -eq 0) { $json='[]' } else { $parts=@($rows | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 16 -Compress }); $json='[' + [Environment]::NewLine + ($parts -join (',' + [Environment]::NewLine)) + [Environment]::NewLine + ']' }; Set-Content -Encoding utf8 -Path 'compile_commands.json' -Value $json" || exit /b 1
      powershell -NoProfile -ExecutionPolicy Bypass -Command "if ($env:INCLUDE) { $inc=$env:INCLUDE } else { $inc='' }; $fingerprint='cflags=' + $env:cflags + [Environment]::NewLine + 'include=' + $inc; Set-Content -Encoding utf8 -Path 'compile_commands.stamp' -Value $fingerprint" || exit /b 1
      del /Q *.ccdb.json >nul 2>&1
      copy /Y compile_commands.json ..\..\compile_commands.json >nul || exit /b 1
    )
  )
) else (
  echo [compile_commands generation skipped; pass compdb to enable]
)
echo [building sokol_sprites.exe]
%compile% ..\..\src\main.c /link /OUT:sokol_sprites.exe d3d11.lib dxgi.lib dxguid.lib kernel32.lib user32.lib gdi32.lib ole32.lib || exit /b 1
popd

echo [output] build\windows\sokol_sprites.exe
if "%want_compile_db%"=="1" echo [output] build\windows\compile_commands.json
