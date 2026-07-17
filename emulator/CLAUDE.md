# CLAUDE.md — RetroGames (emulator/)

## Overview

macOS native emulator frontend using the libretro API. Loads NES/SNES emulation cores (.dylib) at runtime via `dlopen`/`dlsym`.

## Architecture

- **CLibretro** — SPM C target with `libretro.h` (API types/constants) and `shim.c`
- **Emulator** — SwiftUI executable target depending on CLibretro
- **LibretroCore** — Manages core lifecycle, C callbacks route through `LibretroCore.current` static reference
- **AudioEngine** — AVAudioEngine + ring buffer for PCM playback
- **InputManager** — NSEvent keyboard monitors + GameController framework
- **Rendering** — CGImage from frame buffer displayed via CALayer (no Metal shaders)

## Build

```bash
swift build                 # dev build
swift run                   # launch
./build_app.sh              # .app bundle
./install.sh                # build + install to /Applications
```

## Key Directories

- `Sources/CLibretro/` — C interop (libretro.h header)
- `Sources/Emulator/Core/` — LibretroCore, InputManager, EmulatorViewModel
- `Sources/Emulator/Views/` — SwiftUI views
- `Sources/Emulator/Audio/` — Audio engine

## Runtime Directories

- `~/Library/Application Support/RetroGames/Cores/` — libretro .dylib cores
- `~/Library/Application Support/RetroGames/Saves/` — SRAM saves
- `~/Library/Application Support/RetroGames/States/` — save states

## Notes

- Only one core runs at a time (static `LibretroCore.current`)
- Pixel format handling: XRGB8888, RGB565, 0RGB1555
- Core auto-detection by ROM file extension
- Ad-hoc code signing, no entitlements needed for dlopen
