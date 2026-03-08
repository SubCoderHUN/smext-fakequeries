@echo off
REM ===========================================================================
REM  FakeQueries Extension - Windows Build Script
REM  Run from: Developer Command Prompt for VS 2019/2022
REM  Or: x86 Native Tools Command Prompt for VS 2019/2022
REM ===========================================================================

setlocal enabledelayedexpansion

REM -- Configuration ----------------------------------------------------------
REM WORK_DIR = parent of this repo (where SDKs will be cloned as siblings)
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "WORK_DIR=%CD%"
popd

echo.
echo ===================================================================
echo  FakeQueries Extension - Windows Build
echo ===================================================================
echo  Script dir : %SCRIPT_DIR%
echo  SDK root   : %WORK_DIR%
echo ===================================================================
echo.

REM -- Check MSVC -------------------------------------------------------------
where cl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: MSVC compiler 'cl.exe' not found on PATH.
    echo.
    echo You must run this script from one of:
    echo   - "x86 Native Tools Command Prompt for VS 2022"
    echo   - "Developer Command Prompt for VS 2022"  ^(or 2019^)
    echo.
    echo Or run vcvarsall.bat first in a regular cmd:
    echo   "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
    echo.
    echo If you have VS 2019:
    echo   "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
    exit /b 1
)

REM -- Check Python -----------------------------------------------------------
where python >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Python not found. Install Python 3.x and add to PATH.
    echo Download from: https://www.python.org/downloads/
    exit /b 1
)

REM -- Check/install AMBuild --------------------------------------------------
REM Try to find ambuild on PATH first
where ambuild >nul 2>&1
if %ERRORLEVEL% neq 0 (
    REM Also check the user Scripts directory (pip --user install location)
    for /f "delims=" %%i in ('python -c "import site; print(site.getusersitepackages().replace(chr(92)+chr(76)+chr(105)+chr(98), chr(92)+chr(83)+chr(99)+chr(114)+chr(105)+chr(112)+chr(116)+chr(115)))" 2^>nul') do set "USER_SCRIPTS=%%i"
    if defined USER_SCRIPTS (
        if exist "!USER_SCRIPTS!\ambuild.exe" (
            set "PATH=!USER_SCRIPTS!;!PATH!"
            goto :ambuild_found
        )
    )

    echo AMBuild not found. Installing...
    python -m pip install git+https://github.com/alliedmodders/ambuild

    REM Refresh PATH: check common install locations for ambuild
    REM 1. Python Scripts dir (system-wide install)
    for /f "delims=" %%i in ('python -c "import sys,os; print(os.path.join(sys.prefix, 'Scripts'))" 2^>nul') do (
        if exist "%%i\ambuild.exe" set "PATH=%%i;!PATH!"
    )
    REM 2. User Scripts dir (--user install)
    for /f "delims=" %%i in ('python -c "import site; print(site.getusersitepackages().replace(chr(92)+chr(76)+chr(105)+chr(98), chr(92)+chr(83)+chr(99)+chr(114)+chr(105)+chr(112)+chr(116)+chr(115)))" 2^>nul') do (
        if exist "%%i\ambuild.exe" set "PATH=%%i;!PATH!"
    )

    where ambuild >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo.
        echo ERROR: AMBuild was installed but 'ambuild' is not on PATH.
        echo.
        echo Try one of these fixes:
        echo   1. Close and reopen your command prompt, then run this script again
        echo   2. Or add Python's Scripts directory to your PATH manually:
        echo      For system Python:  where python  ^(look at the directory^)
        echo      Add: ^<that directory^>\Scripts  to your PATH
        echo   3. Or install globally:  python -m pip install --force-reinstall git+https://github.com/alliedmodders/ambuild
        exit /b 1
    )
)
:ambuild_found
echo Found AMBuild:
where ambuild

REM -- Clone SDKs if not present ----------------------------------------------
cd /d "%WORK_DIR%"

if not exist "hl2sdk-csgo" (
    echo.
    echo Cloning HL2SDK ^(CSGO branch^)...
    git clone --depth 1 -b csgo https://github.com/alliedmodders/hl2sdk.git hl2sdk-csgo
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to clone HL2SDK.
        exit /b 1
    )
) else (
    echo Found hl2sdk-csgo: %WORK_DIR%\hl2sdk-csgo
)

if not exist "metamod-source" (
    echo.
    echo Cloning Metamod:Source...
    git clone --depth 1 https://github.com/alliedmodders/metamod-source.git metamod-source
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to clone Metamod:Source.
        exit /b 1
    )
) else (
    echo Found metamod-source: %WORK_DIR%\metamod-source
)

if not exist "sourcemod" (
    echo.
    echo Cloning SourceMod 1.8-dev...
    git clone --depth 1 -b 1.8-dev https://github.com/alliedmodders/sourcemod.git sourcemod
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to clone SourceMod.
        exit /b 1
    )
    echo Initializing SourceMod submodules...
    cd sourcemod
    git submodule update --init --depth 1
    cd ..
) else (
    echo Found sourcemod: %WORK_DIR%\sourcemod
    REM Ensure submodules are initialized
    if not exist "sourcemod\public\amtl\amtl" (
        echo Initializing SourceMod submodules...
        cd sourcemod
        git submodule update --init --depth 1
        cd ..
    )
)

REM -- Verify required lib files exist ----------------------------------------
echo.
echo Verifying HL2SDK libraries...
set "MISSING_LIBS=0"
for %%L in (tier0 tier1 vstdlib mathlib interfaces steam_api) do (
    if not exist "hl2sdk-csgo\lib\public\%%L.lib" (
        echo   MISSING: hl2sdk-csgo\lib\public\%%L.lib
        set "MISSING_LIBS=1"
    )
)
if "%MISSING_LIBS%"=="1" (
    echo.
    echo WARNING: Some .lib files are missing from hl2sdk-csgo\lib\public\
    echo The linker step may fail. Check your HL2SDK clone.
    echo.
)

REM -- Configure and Build ----------------------------------------------------
cd /d "%SCRIPT_DIR%"

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
    echo.
    echo ERROR: Configure failed. Check the output above for details.
    exit /b 1
)

echo.
echo === Building ===
ambuild
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Build failed. Check the compiler output above for details.
    exit /b 1
)

echo.
echo ===================================================================
echo  BUILD SUCCESSFUL!
echo ===================================================================
echo.

if exist "fakequeries.ext.2.csgo\fakequeries.ext.2.csgo.dll" (
    echo Output DLL:
    echo   %CD%\fakequeries.ext.2.csgo\fakequeries.ext.2.csgo.dll
) else (
    echo Output files in: %CD%\fakequeries.ext.2.csgo\
)

echo.
echo Package directory ^(ready to deploy^):
echo   %CD%\fakequeries\addons\sourcemod\
echo.
echo To install on your CS:GO server, copy the 'addons' folder from
echo the package directory into your server's 'csgo\' directory.
echo.
echo Required server files:
echo   csgo\addons\sourcemod\extensions\fakequeries.ext.2.csgo.dll
echo   csgo\addons\sourcemod\gamedata\fakequeries.games.txt
echo ===================================================================

endlocal
