# Build Guide for sm-ext-fakequeries

This guide covers building the FakeQueries SourceMod extension for CS:GO and installing it on a **Windows dedicated server**.

## Overview

FakeQueries is a SourceMod extension that intercepts and returns custom (fake) A2S_INFO and A2S_PLAYER responses. This lets you control what the server browser displays: server name, map, player count, fake players, tags, and more.

It uses the **AMBuild** build system and requires three external SDKs:

1. **HL2SDK** (CSGO branch)
2. **Metamod:Source**
3. **SourceMod** (1.8-dev branch, with submodules)

---

## Full Dependency List

| Dependency | Version | Purpose |
|---|---|---|
| Python | 3.x | Required by AMBuild |
| AMBuild | 2.x | Build system (alliedmodders/ambuild) |
| HL2SDK (csgo branch) | Latest | Half-Life 2 SDK headers and libraries |
| Metamod:Source | Latest | Metamod headers (ISmmPlugin, SourceHook) |
| SourceMod | 1.8-dev | SourceMod public headers, CDetour, asm |
| Visual Studio (Windows) | 2015 / 2017 / 2019 / 2022 | MSVC x86 C/C++ compiler |
| Git for Windows | Any | To clone repositories |
| GCC/G++ (Linux only) | Any recent | 32-bit C/C++ compiler with multilib |
| gcc-multilib / g++-multilib (Linux only) | - | 32-bit cross compilation support |

---

## Windows Build (Step-by-Step) — Target: x86 .dll

### 1. Install Required Software

#### a) Python 3.x
- Download from https://www.python.org/downloads/
- **Check "Add Python to PATH"** during installation
- Verify in cmd: `python --version`

#### b) Visual Studio 2019 or 2022
- Download Visual Studio Community from https://visualstudio.microsoft.com/
- Install with the **"Desktop development with C++"** workload
- Make sure **MSVC v142/v143 x86/x64 build tools** and **Windows 10/11 SDK** are checked

#### c) Git for Windows
- Download from https://git-scm.com/download/win
- Use default installation options

#### d) AMBuild
Open a regular command prompt (cmd) or PowerShell:
```cmd
pip install git+https://github.com/alliedmodders/ambuild
```
Verify: `ambuild --version`

### 2. Clone All Repositories

Open **cmd** or **PowerShell**:

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

Your directory structure must look like:
```
C:\sourcemod-dev\
├── hl2sdk-csgo\          # HL2SDK CSGO branch
├── metamod-source\       # Metamod:Source source
├── sourcemod\            # SourceMod 1.8-dev (with submodules initialized)
└── smext-fakequeries\    # This extension
```

### 3. Configure and Build

**CRITICAL**: You MUST run the build from a **Developer Command Prompt for VS 2019/2022** (or **x86 Native Tools Command Prompt for VS**) so that the MSVC compiler (`cl.exe`) is available.

How to open it:
- Start Menu > search for **"Developer Command Prompt for VS 2022"** (or 2019)
- Or run this first in a regular cmd:
  ```cmd
  "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
  ```

Then build:

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

For a release/optimized build, add `--enable-optimize`:
```cmd
python ..\configure.py ^
  --sm-path=C:\sourcemod-dev\sourcemod ^
  --mms-path=C:\sourcemod-dev\metamod-source ^
  --hl2sdk-root=C:\sourcemod-dev ^
  -s csgo ^
  --enable-optimize
```

### 4. Automated Build Script

Alternatively, use the included `build_windows.bat` script which automates the entire process (cloning SDKs, configuring, building):

```cmd
cd C:\sourcemod-dev\smext-fakequeries
build_windows.bat
```

### 5. Build Output

After a successful build, the compiled **32-bit Windows DLL** is at:
```
C:\sourcemod-dev\smext-fakequeries\build\fakequeries.ext.2.csgo\fakequeries.ext.2.csgo.dll
```

The complete deployable package is at:
```
C:\sourcemod-dev\smext-fakequeries\build\fakequeries\addons\sourcemod\
├── extensions\
│   └── fakequeries.ext.2.csgo.dll     # The compiled extension
├── gamedata\
│   └── fakequeries.games.txt          # Required gamedata (signatures/offsets)
└── scripting\
    ├── include\
    │   └── fakequeries.inc             # SourcePawn include for plugin developers
    └── example_fakeplayers.sp          # Example plugin
```

---

## Installing on a Windows CS:GO Dedicated Server

### Prerequisites

Your server must have:
- **Metamod:Source** installed (https://www.sourcemm.net/)
- **SourceMod** installed (https://www.sourcemod.net/)

Both must be working — verify with `meta list` and `sm version` in the server console.

### Step 1: Copy the Extension DLL

Copy `fakequeries.ext.2.csgo.dll` to:
```
<server>\csgo\addons\sourcemod\extensions\fakequeries.ext.2.csgo.dll
```

### Step 2: Copy the GameData File

Copy `fakequeries.games.txt` to:
```
<server>\csgo\addons\sourcemod\gamedata\fakequeries.games.txt
```

**This file is REQUIRED.** The extension will fail to load without it. It contains memory signatures and offsets for hooking the Steam query system.

### Step 3: Copy the SourcePawn Include (for plugin development)

Copy `fakequeries.inc` to:
```
<server>\csgo\addons\sourcemod\scripting\include\fakequeries.inc
```

### Step 4: Install a Plugin That Uses the Extension

The extension itself does nothing until a SourcePawn plugin calls its natives. Copy the example plugin:
```
<server>\csgo\addons\sourcemod\scripting\example_fakeplayers.sp
```

Compile it with `spcomp`:
```cmd
cd <server>\csgo\addons\sourcemod\scripting
spcomp example_fakeplayers.sp
```

Then move the compiled `.smx` to the plugins directory:
```
<server>\csgo\addons\sourcemod\plugins\example_fakeplayers.smx
```

### Complete Server File Structure

After installation, your server should have:
```
<server>\csgo\
└── addons\
    └── sourcemod\
        ├── extensions\
        │   └── fakequeries.ext.2.csgo.dll
        ├── gamedata\
        │   └── fakequeries.games.txt
        ├── plugins\
        │   └── example_fakeplayers.smx      (or your own plugin)
        └── scripting\
            ├── include\
            │   └── fakequeries.inc
            └── example_fakeplayers.sp
```

### Step 5: Restart the Server and Verify

Restart your CS:GO server (or change the map), then check:

#### Verify extension is loaded
In the server console, type:
```
sm exts list
```

You should see something like:
```
[XX] FakeQueries (X.X.X): Fake A2S_INFO and A2S_PLAYER Responses
```

#### Verify plugin is loaded
```
sm plugins list
```

You should see:
```
[XX] "Example - Fake players" (1.3.2) by yourmnbbn
```

#### Check for errors
If the extension failed to load, check:
```
<server>\csgo\addons\sourcemod\logs\errors_YYYYMMDD.log
```

Common errors and fixes:
- **"Could not read fakequeries.games"** — `fakequeries.games.txt` is missing from `gamedata/`
- **"Failed to get address of g_pSteamSocketMgr"** — Gamedata signatures are outdated for your CS:GO version. You may need to update the signatures in `fakequeries.games.txt`.
- **"Error reading steam.inf"** — The `steam.inf` file in your CS:GO server root is missing or corrupted.

#### Test A2S response
From another machine, use a Steam server query tool or `python-a2s`:
```bash
pip install python-a2s
python -c "import a2s; print(a2s.info(('YOUR_SERVER_IP', 27015)))"
```
You should see the fake player names and modified server info.

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
mkdir -p ~/sourcemod-dev && cd ~/sourcemod-dev

git clone https://github.com/SubCoderHUN/smext-fakequeries.git
cd ..
git clone --depth 1 -b csgo https://github.com/alliedmodders/hl2sdk.git hl2sdk-csgo
git clone --depth 1 https://github.com/alliedmodders/metamod-source.git metamod-source
git clone --depth 1 -b 1.8-dev https://github.com/alliedmodders/sourcemod.git sourcemod
cd sourcemod && git submodule update --init --depth 1 && cd ..
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

```
build/fakequeries.ext.2.csgo/fakequeries.ext.2.csgo.so
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

Or place the SDK folders in a parent directory of the extension source — AMBuild will search upward automatically.

---

## Troubleshooting

### Build Issues

#### `Could not find a valid path for HL2SDKCSGO`
- Ensure the `hl2sdk-csgo` directory exists and is named **exactly** `hl2sdk-csgo`
- The `--hl2sdk-root` must point to the **parent** directory that contains `hl2sdk-csgo/`

#### `Could not find a source copy of SourceMod`
- Ensure you cloned the **source code** of SourceMod (not a binary release)
- Must use the `1.8-dev` branch: `git clone -b 1.8-dev ...`
- Initialize submodules: `cd sourcemod && git submodule update --init`

#### `Could not find a source copy of Metamod:Source`
- Ensure `metamod-source/` exists with the full source tree (not a binary release)

#### MSVC / `cl.exe` not found on Windows
- Run from **Developer Command Prompt for VS** or **x86 Native Tools Command Prompt**
- Or run: `"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x86`

#### Linker errors on Windows (missing .lib files)
- Verify `hl2sdk-csgo\lib\public\` contains: `tier0.lib`, `tier1.lib`, `vstdlib.lib`, `mathlib.lib`, `interfaces.lib`, `steam_api.lib`

#### 32-bit compilation fails on Linux
- Install multilib: `sudo apt-get install gcc-multilib g++-multilib`

### Runtime Issues (Server)

#### Extension fails to load with signature errors
- The gamedata signatures in `fakequeries.games.txt` are for a specific CS:GO version. If Valve updates the game, signatures may break. You'll need to find updated signatures using tools like IDA Pro or Ghidra.

#### `sm exts list` shows the extension as "FAILED"
- Run `sm exts info <number>` for the specific error message
- Check `addons/sourcemod/logs/` for detailed error logs

#### Extension loads but fake queries don't work
- Make sure a plugin is calling `FQ_ToggleStatus(true)` — the extension is **disabled by default**
- Ensure `host_info_show` is set to 1 or 2 (server cvar)
- Ensure `host_players_show` is set to 1 or 2 for A2S_PLAYER responses

---

## API Quick Reference

Key natives available to SourcePawn plugins (see `fakequeries.inc` for full docs):

| Native | Description |
|---|---|
| `FQ_ToggleStatus(bool)` | Enable/disable the extension (disabled by default) |
| `FQ_ResetA2sInfo()` | Reset all A2S_INFO modifications to defaults |
| `FQ_SetServerName(name)` | Override displayed server name |
| `FQ_SetMapName(name)` | Override displayed map name |
| `FQ_SetNumClients(n)` | Override displayed player count |
| `FQ_SetMaxClients(n)` | Override displayed max players |
| `FQ_SetNumFakeClients(n)` | Override displayed bot count |
| `FQ_AddFakePlayer(idx, name, score, time)` | Add a fake player to A2S_PLAYER |
| `FQ_RemoveFakePlayer(idx)` | Remove fake player by index |
| `FQ_RemoveAllFakePlayer()` | Remove all fake players |
| `FQ_InfoResponseAutoPlayerCount(bool)` | Auto-adjust player count based on fake players |
| `FQ_SetServerTag(tags)` | Override server tags |
| `FQ_SetOS(OS)` | Override displayed server OS |
| `FQ_SetVacStatus(bool)` | Override displayed VAC status |
| `FQ_SetGameVersion(ver)` | Override displayed game version |
| `FQ_SetEDF(flags)` | Control which extra data fields are sent |

---

## Changes Made to Build with Modern Toolchains

Two fixes were required to build with modern compilers:

1. **AMBuilder**: Removed references to `libudis86` (`udis86.c`, `decode.c`, `itab.c`) — these files no longer exist in SourceMod 1.8-dev. The CDetour module now uses the `asm` module instead.

2. **AMBuildScript**: Added `-Wno-maybe-uninitialized` for GCC 12+ to suppress false positive warnings from SourceHook macro expansions.
