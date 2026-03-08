# Build Guide for sm-ext-fakequeries

This guide covers building the FakeQueries SourceMod extension for CSGO on both Linux and Windows.

## Overview

FakeQueries is a SourceMod extension that returns fake A2S_INFO and A2S_PLAYER responses. It uses the **AMBuild** build system and requires three external SDKs:

1. **HL2SDK** (CSGO branch)
2. **Metamod:Source**
3. **SourceMod** (1.8-dev branch, with submodules)

---

## Full Dependency List

| Dependency | Version | Purpose |
|---|---|---|
| Python | 3.x | Required by AMBuild |
| AMBuild | 2.x | Build system |
| HL2SDK (csgo branch) | Latest | Half-Life 2 SDK headers and libraries |
| Metamod:Source | Latest | Metamod headers (ISmmPlugin, SourceHook) |
| SourceMod | 1.8-dev | SourceMod public headers, CDetour, asm |
| GCC/G++ (Linux) | Any recent | 32-bit C/C++ compiler with multilib |
| Visual Studio (Windows) | 2015-2022 | MSVC C/C++ compiler |
| gcc-multilib / g++-multilib (Linux) | - | 32-bit cross compilation support |

---

## Linux Build (Tested & Working)

### 1. Install system packages

```bash
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y python3 python3-pip gcc g++ gcc-multilib g++-multilib git
```

### 2. Install AMBuild

```bash
pip3 install git+https://github.com/alliedmodders/ambuild
```

### 3. Clone the SDKs

All SDKs should be in the **same parent directory** as the extension source:

```bash
# Choose a workspace directory
mkdir -p ~/sourcemod-dev && cd ~/sourcemod-dev

# Clone the extension
git clone https://github.com/SubCoderHUN/smext-fakequeries.git
cd smext-fakequeries

# Clone HL2SDK (CSGO branch) - must be named hl2sdk-csgo
cd ..
git clone --depth 1 -b csgo https://github.com/alliedmodders/hl2sdk.git hl2sdk-csgo

# Clone Metamod:Source
git clone --depth 1 https://github.com/alliedmodders/metamod-source.git metamod-source

# Clone SourceMod (1.8-dev branch) with submodules
git clone --depth 1 -b 1.8-dev https://github.com/alliedmodders/sourcemod.git sourcemod
cd sourcemod && git submodule update --init --depth 1 && cd ..
```

Your directory structure should look like:

```
~/sourcemod-dev/
├── hl2sdk-csgo/          # HL2SDK CSGO branch
├── metamod-source/       # Metamod:Source
├── sourcemod/            # SourceMod 1.8-dev (with submodules initialized)
└── smext-fakequeries/    # This extension
```

### 4. Configure and Build

```bash
cd ~/sourcemod-dev/smext-fakequeries
mkdir build && cd build

python3 ../configure.py \
  --sm-path=../../sourcemod \
  --mms-path=../../metamod-source \
  --hl2sdk-root=../../ \
  -s csgo

ambuild
```

### 5. Output

The compiled binary will be at:
```
build/fakequeries.ext.2.csgo/fakequeries.ext.2.csgo.so
```

A ready-to-deploy package structure is also created at:
```
build/fakequeries/addons/sourcemod/extensions/fakequeries.ext.2.csgo.so
```

---

## Windows Build (Step-by-Step)

### 1. Install Required Software

#### Python 3.x
- Download from https://www.python.org/downloads/
- **Check "Add Python to PATH"** during installation
- Verify: `python --version`

#### Visual Studio 2019 or 2022
- Download Visual Studio Community from https://visualstudio.microsoft.com/
- Install with the **"Desktop development with C++"** workload
- Make sure the **MSVC v142/v143 x86/x64 build tools** are selected

#### Git for Windows
- Download from https://git-scm.com/download/win

#### AMBuild
Open a command prompt (cmd) or PowerShell:
```cmd
pip install git+https://github.com/alliedmodders/ambuild
```

### 2. Clone the SDKs

Open **Developer Command Prompt for VS 2019/2022** (or a regular cmd):

```cmd
mkdir C:\sourcemod-dev
cd C:\sourcemod-dev

git clone https://github.com/SubCoderHUN/smext-fakequeries.git
git clone --depth 1 -b csgo https://github.com/alliedmodders/hl2sdk.git hl2sdk-csgo
git clone --depth 1 https://github.com/alliedmodders/metamod-source.git metamod-source
git clone --depth 1 -b 1.8-dev https://github.com/alliedmodders/sourcemod.git sourcemod
cd sourcemod
git submodule update --init --depth 1
cd ..
```

### 3. Configure and Build

**IMPORTANT**: You MUST run the build from a **Developer Command Prompt for VS** (or run `vcvarsall.bat x86` first) so that MSVC is on the PATH.

```cmd
cd C:\sourcemod-dev\smext-fakequeries
mkdir build
cd build

python ..\configure.py ^
  --sm-path=C:\sourcemod-dev\sourcemod ^
  --mms-path=C:\sourcemod-dev\metamod-source ^
  --hl2sdk-root=C:\sourcemod-dev ^
  -s csgo

ambuild
```

### 4. Output

The compiled binary will be at:
```
build\fakequeries.ext.2.csgo\fakequeries.ext.2.csgo.dll
```

---

## Alternative: Using Environment Variables

Instead of passing `--hl2sdk-root`, `--sm-path`, and `--mms-path`, you can set environment variables:

```bash
# Linux
export HL2SDKCSGO=/path/to/hl2sdk-csgo
export SOURCEMOD18=/path/to/sourcemod
export MMSOURCE110=/path/to/metamod-source

# Windows (cmd)
set HL2SDKCSGO=C:\sourcemod-dev\hl2sdk-csgo
set SOURCEMOD18=C:\sourcemod-dev\sourcemod
set MMSOURCE110=C:\sourcemod-dev\metamod-source
```

Or place the SDK folders in a parent directory of the extension source - AMBuild will search upward automatically.

---

## Troubleshooting

### `Could not find a valid path for HL2SDKCSGO`
- Ensure the `hl2sdk-csgo` directory exists and is named **exactly** `hl2sdk-csgo`
- Pass the correct `--hl2sdk-root` (the **parent** directory containing `hl2sdk-csgo/`)

### `Could not find a source copy of SourceMod`
- Ensure you cloned the **source code** of SourceMod (not a release binary)
- Use the `1.8-dev` branch: `git clone -b 1.8-dev https://github.com/alliedmodders/sourcemod.git`
- Initialize submodules: `cd sourcemod && git submodule update --init`

### `Could not find a source copy of Metamod:Source`
- Ensure `metamod-source/` directory exists with the full source (not a release)

### `libudis86` files not found
- The original AMBuilder referenced `libudis86` files that no longer exist in modern SourceMod 1.8+
- The fix applied in this repo removes those references (they are no longer needed)

### `-Werror=maybe-uninitialized` on GCC 12+
- Newer GCC versions trigger a false positive from SourceHook macros
- The fix applied in this repo adds `-Wno-maybe-uninitialized` for GCC 12+

### 32-bit compilation fails on Linux
- Install multilib packages: `sudo apt-get install gcc-multilib g++-multilib`

### MSVC not found on Windows
- Run from **Developer Command Prompt for VS** (not regular cmd/PowerShell)
- Or run: `"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x86`

### Linker errors on Windows (missing .lib files)
- Verify `hl2sdk-csgo/lib/public/` contains `tier0.lib`, `tier1.lib`, `vstdlib.lib`, `mathlib.lib`, `interfaces.lib`, `steam_api.lib`

---

## Changes Made to Build with Modern Toolchains

Two fixes were required to build with modern compilers:

1. **AMBuilder**: Removed references to `libudis86` (udis86.c, decode.c, itab.c) - these files no longer exist in SourceMod 1.8-dev. The CDetour module now uses the `asm` module instead.

2. **AMBuildScript**: Added `-Wno-maybe-uninitialized` for GCC 12+ to suppress false positive warnings from SourceHook macro expansions.
