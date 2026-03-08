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
call :find_ambuild
if !ERRORLEVEL! equ 0 goto :ambuild_ready

echo AMBuild not found. Installing...
python -m pip install git+https://github.com/alliedmodders/ambuild

call :find_ambuild
if !ERRORLEVEL! equ 0 goto :ambuild_ready

echo.
echo ERROR: AMBuild was installed but 'ambuild' could not be found.
echo.
echo Diagnostic info:
python -c "import ambuild2; print('  ambuild2 package found at:', ambuild2.__file__)" 2>nul
if %ERRORLEVEL% neq 0 echo   ambuild2 package NOT importable - install may have failed
echo.
echo Please do the following manually:
echo   1. Run: python -m pip install git+https://github.com/alliedmodders/ambuild
echo   2. Run: python -c "import sysconfig; print(sysconfig.get_path('scripts',scheme='nt_user'))"
echo   3. Add the printed path to your system PATH
echo   4. Close and reopen your terminal
echo   5. Run build_windows.bat again
exit /b 1

:ambuild_ready
echo Found AMBuild: !AMBUILD_EXE!
echo.

REM -- Clone SDKs if not present ----------------------------------------------
cd /d "%WORK_DIR%"

if not exist "hl2sdk-csgo" (
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
if "!MISSING_LIBS!"=="1" (
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
"!AMBUILD_EXE!"
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
exit /b 0

REM ===========================================================================
REM  Subroutine: find_ambuild
REM  Searches for ambuild.exe in multiple locations and sets AMBUILD_EXE
REM  Returns 0 if found, 1 if not found
REM ===========================================================================
:find_ambuild
set "AMBUILD_EXE="

REM 1. Check if already on PATH
where ambuild.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    for /f "delims=" %%p in ('where ambuild.exe') do (
        set "AMBUILD_EXE=%%p"
        exit /b 0
    )
)

REM 2. Ask Python for the user scripts directory (works with Windows Store Python)
for /f "delims=" %%d in ('python -c "import sysconfig; print(sysconfig.get_path('scripts',scheme='nt_user'))" 2^>nul') do (
    if exist "%%d\ambuild.exe" (
        set "AMBUILD_EXE=%%d\ambuild.exe"
        set "PATH=%%d;!PATH!"
        exit /b 0
    )
)

REM 3. Ask Python for the system scripts directory
for /f "delims=" %%d in ('python -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2^>nul') do (
    if exist "%%d\ambuild.exe" (
        set "AMBUILD_EXE=%%d\ambuild.exe"
        set "PATH=%%d;!PATH!"
        exit /b 0
    )
)

REM 4. Check sys.prefix\Scripts (fallback)
for /f "delims=" %%d in ('python -c "import sys,os; print(os.path.join(sys.prefix,'Scripts'))" 2^>nul') do (
    if exist "%%d\ambuild.exe" (
        set "AMBUILD_EXE=%%d\ambuild.exe"
        set "PATH=%%d;!PATH!"
        exit /b 0
    )
)

REM 5. Check APPDATA Python Scripts (common Windows Store Python location)
if defined APPDATA (
    for /d %%v in ("%APPDATA%\Python\Python*") do (
        if exist "%%v\Scripts\ambuild.exe" (
            set "AMBUILD_EXE=%%v\Scripts\ambuild.exe"
            set "PATH=%%v\Scripts;!PATH!"
            exit /b 0
        )
    )
)

REM 6. Check LocalAppData for Windows Store Python packages
if defined LOCALAPPDATA (
    for /d %%p in ("%LOCALAPPDATA%\Packages\PythonSoftwareFoundation*") do (
        for /d %%v in ("%%p\LocalCache\local-packages\Python*") do (
            if exist "%%v\Scripts\ambuild.exe" (
                set "AMBUILD_EXE=%%v\Scripts\ambuild.exe"
                set "PATH=%%v\Scripts;!PATH!"
                exit /b 0
            )
        )
    )
)

exit /b 1
