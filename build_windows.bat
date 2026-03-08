@echo off
REM ===========================================================================
REM  FakeQueries Extension - Windows Build Script
REM  Run from: Developer Command Prompt for VS 2019/2022
REM  Or: x86 Native Tools Command Prompt for VS 2019/2022
REM ===========================================================================

setlocal enabledelayedexpansion

REM -- Configuration ----------------------------------------------------------
set "WORK_DIR=%~dp0.."
set "BUILD_DIR=%~dp0build"

REM Check if we're in a VS developer prompt
where cl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: MSVC compiler 'cl.exe' not found on PATH.
    echo.
    echo You must run this script from one of:
    echo   - "Developer Command Prompt for VS 2019/2022"
    echo   - "x86 Native Tools Command Prompt for VS 2019/2022"
    echo.
    echo Or run vcvarsall.bat first:
    echo   "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
    exit /b 1
)

REM Check Python
where python >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Python not found. Install Python 3.x and add to PATH.
    exit /b 1
)

REM Check AMBuild
where ambuild >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo AMBuild not found. Installing...
    pip install git+https://github.com/alliedmodders/ambuild
    if %ERRORLEVEL% neq 0 (
        echo ERROR: Failed to install AMBuild.
        exit /b 1
    )
)

REM -- Clone SDKs if not present ----------------------------------------------
cd /d "%WORK_DIR%"

if not exist "hl2sdk-csgo" (
    echo Cloning HL2SDK ^(CSGO branch^)...
    git clone --depth 1 -b csgo https://github.com/alliedmodders/hl2sdk.git hl2sdk-csgo
    if %ERRORLEVEL% neq 0 (
        echo ERROR: Failed to clone HL2SDK.
        exit /b 1
    )
)

if not exist "metamod-source" (
    echo Cloning Metamod:Source...
    git clone --depth 1 https://github.com/alliedmodders/metamod-source.git metamod-source
    if %ERRORLEVEL% neq 0 (
        echo ERROR: Failed to clone Metamod:Source.
        exit /b 1
    )
)

if not exist "sourcemod" (
    echo Cloning SourceMod 1.8-dev...
    git clone --depth 1 -b 1.8-dev https://github.com/alliedmodders/sourcemod.git sourcemod
    if %ERRORLEVEL% neq 0 (
        echo ERROR: Failed to clone SourceMod.
        exit /b 1
    )
    cd sourcemod
    git submodule update --init --depth 1
    cd ..
)

REM -- Configure and Build ----------------------------------------------------
cd /d "%~dp0"

if exist build (
    echo Cleaning previous build...
    rmdir /s /q build
)

mkdir build
cd build

echo.
echo === Configuring ===
python ..\configure.py --sm-path="%WORK_DIR%\sourcemod" --mms-path="%WORK_DIR%\metamod-source" --hl2sdk-root="%WORK_DIR%" -s csgo --enable-optimize
if %ERRORLEVEL% neq 0 (
    echo ERROR: Configure failed.
    exit /b 1
)

echo.
echo === Building ===
ambuild
if %ERRORLEVEL% neq 0 (
    echo ERROR: Build failed.
    exit /b 1
)

echo.
echo ===================================================================
echo  BUILD SUCCESSFUL!
echo ===================================================================
echo.
echo Output DLL:
echo   %CD%\fakequeries.ext.2.csgo\fakequeries.ext.2.csgo.dll
echo.
echo Package directory:
echo   %CD%\fakequeries\addons\sourcemod\
echo.
echo Copy the 'addons' folder from the package directory into your
echo CS:GO server's 'csgo/' directory.
echo ===================================================================

endlocal
