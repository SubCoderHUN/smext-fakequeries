@echo off
REM Build Linux .so extension from Windows using Docker
REM Requirements: Docker Desktop for Windows
REM
REM Usage:
REM   build-linux.bat          - Build with defaults (CS:GO SDK)
REM   build-linux.bat tf2      - Build with specific SDK

setlocal

set SDK=%1
if "%SDK%"=="" set SDK=csgo

echo ============================================
echo  Building fakequeries Linux .so extension
echo  SDK: %SDK%
echo ============================================

REM Build the Docker image (which compiles the extension)
docker build -f Dockerfile.linux-build --build-arg SDKS=%SDK% -t fakequeries-linux-build .
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Docker build failed!
    echo Make sure Docker Desktop is installed and running.
    exit /b 1
)

REM Create output directory
if not exist "build-output" mkdir build-output

REM Copy the built files out of the container
docker create --name fq-extract fakequeries-linux-build >nul 2>&1
docker cp fq-extract:/build/smext-fakequeries/build/fakequeries/. build-output/
docker rm fq-extract >nul 2>&1

echo.
echo ============================================
echo  Build complete!
echo  Output files are in: build-output\
echo ============================================
dir /s /b build-output\*.so 2>nul

endlocal
