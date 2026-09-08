# CLAUDE.md — MyGames (mygames/)

## Overview

macOS native emulator frontend using the libretro API. Loads NES/SNES emulation cores (.dylib) at runtime via `dlopen`/`dlsym`.

## Architecture

- **CLibretro** — SPM C target with `libretro.h` (API types/constants) and `shim.c`. `shim.c` provides the variadic `retro_log_printf_t` for `GET_LOG_INTERFACE` (Swift can't create variadic C fn pointers) — without it cores call a NULL log callback and SIGSEGV (e.g. nestopia on CPU JAM)
- **MyGames** — SwiftUI executable target depending on CLibretro
- **LibretroCore** — Manages core lifecycle, C callbacks route through `LibretroCore.current` static reference
- **AudioEngine** — AVAudioEngine + ring buffer for PCM playback
- **InputManager** — NSEvent keyboard monitors + GameController framework. Esc / ⌘W → stop (handled in the keyDown monitor, not menu shortcuts). Gamepad button bindings come from `ControllerConfig.shared.mapping` (re-read at each game start); dpad + left thumbstick are fixed to movement
- **ControllerConfig** — controller connect/disconnect tracking + physical→virtual button mapping persisted in UserDefaults (`controllerMapping`); "press to assign" capture via profile-level `valueChangedHandler` (doesn't conflict with InputManager's per-button handlers). UI is the コントローラー tab (`ControllerSettingsView`)
- **Rendering** — CGImage from frame buffer displayed via CALayer (no Metal shaders)
- **BoardGames tab** — absorbed the former standalone `boardgames` app (将棋・チェス・オセロ・囲碁・五目並べ・麻雀・ダイヤモンドゲームの7種、SwiftUIネイティブ、AI対戦あり) as the「ボードゲーム」tab; do not re-add `boardgames` as a separate app. `Sources/MyGames/BoardGames/` is a straight file-move from the old `boardgames/Sources/` — its own module structure (7 independent `*Engine.swift`/`*Game.swift`/`*Views.swift` sets + shared `Shared.swift`) is unchanged, only `main.swift`'s `@main App`/`WindowGroup` wrapper was stripped and its `RootView` renamed to `BoardGamesRootView` (rendered from `ContentView`'s `.boardgames` tab case). The `Router` + 7 `GameState` `@StateObject`s live in `MyGamesApp` (`Main.swift`) and reach `BoardGamesRootView` via `environmentObject` propagation, same pattern as the emulator side. Saves are per-game JSON slots at `~/Library/Application Support/BoardGames/<game>/slotN.json` (unrelated to the `MyGames/` save directories below, no bundle-ID dependency so pre-merge saves carry over unchanged).
  - **2人対戦モード (2026-09-07, ユーザー指示)** — 将棋・チェス・オセロ・囲碁・五目並べ・ダイヤモンドゲームの6種(麻雀を除く。4人前提のゲームなので1人プレイ vs AI×3のみ、2人対戦は追加していない)に、同じ画面で2人が交互に指す「2人対戦」モードを追加。`Shared.swift`の`OpponentMode`(`.ai`/`.human`)を各`*GameState`に`@Published var opponentMode`として追加し、`didSet`でモード切り替え時にAI思考中なら中断・AI番なら即座に着手させる。各ゲームの実装パターン: `isHumanTurn`を`opponentMode == .human || position.sideToMove == humanX`に一般化、駒/コマの選択可否チェックを固定の`humanColor`ではなく`position.sideToMove`ベースに変更、`scheduleAIMove()`の先頭に`guard opponentMode == .ai`を追加、勝敗・手番アナウンスのメッセージ文言を`opponentMode == .human`のときだけ「あなた/相手」ではなく実際の色・駒名(黒/白、先手/後手など)で組み立てるよう分岐、`undo()`は2人対戦時は1手のみ戻す(AI対戦時は自分の手+AI応手の2手)。ヒントボタンは2人対戦では非表示(一方だけAIの示す最善手を見られると不公平なため)。各`*Save`構造体に`var opponentMode: OpponentMode?`をoptionalで追加(既存セーブとの互換性のため、nilならAI対戦として復元)。**iPad版(`mygames-ipad/`)にも同じ変更を反映済み** — 変更したら両方に適用すること。

## Build

```bash
swift build                 # コンパイル確認のみ(GUI 起動・目視確認は禁止 — ルート CLAUDE.md 参照)
./build_app.sh              # .app bundle
./install.sh                # build + install to /Applications/MyApplications
```

コード変更後は `swift build` 止まりにせず `./install.sh` まで実行する(ユーザー要望)。install.sh は起動中の MyGames を自動終了してからコピーする。C ヘッダ追加後にビルドが「cannot find ... in scope」で落ちる場合は stale module cache なので `rm -rf .build`。

## Key Directories

- `Sources/CLibretro/` — C interop (libretro.h header)
- `Sources/MyGames/Core/` — LibretroCore, InputManager, EmulatorViewModel
- `Sources/MyGames/Views/` — SwiftUI views
- `Sources/MyGames/Audio/` — Audio engine
- `Sources/MyGames/BoardGames/` — 「ボードゲーム」タブ(旧 boardgames アプリ、7種の対戦ゲーム)

## Runtime Directories

- `~/Library/Application Support/MyGames/Cores/` — libretro .dylib cores
- `~/Library/Application Support/MyGames/Saves/` — SRAM saves (`<ROM名>.srm`, per game; the old shared `game.srm` is orphaned and no longer read)
- `~/Library/Application Support/MyGames/States/` — save states (`<ROM名>.state`, per game)

## Notes

- Only one core runs at a time (static `LibretroCore.current`)
- Pixel format handling: XRGB8888, RGB565, 0RGB1555
- Core auto-detection by ROM file extension
- Ad-hoc code signing, no entitlements needed for dlopen
- ROM scan (`ROMScanner`) is recursive (deep `FileManager.enumerator`); only bare `.nes`/`.sfc`/`.smc` files are supported — `.7z`/`.zip` support was removed intentionally (2026-07, ユーザー要望), do not re-add it. Access failures (TCC 等) surface via `scanner.scanError`.
- Library deletion: right-click a card or ⌘クリック multi-select → ゴミ箱. `ROMScanner.moveToTrash` trashes the ROM file (`FileManager.trashItem` — never hard delete, per repo convention).
- Library pages (`LibraryPage` chips): ファミコン / スーパーファミコン / お気に入り / よく起動(起動回数トップ20). `LibraryStore` persists favorites (`favoriteROMs`) and launch counts (`launchCounts`) in UserDefaults, keyed by `ScannedROM.id`.
- Boxart: fetched from libretro-thumbnails (No-Intro naming) via `ThumbnailLoader` (max 6 concurrent, transient errors retried with backoff). Japan-region art is preferred — `ScannedROM.thumbnailCandidates` tries `(Japan)` / `(Japan, USA)` / `(World)` before the ROM's own region tag. CJK-titled files are resolved through `TitleMap` (keys `"NES|日本語タイトル"` NFC-normalized → romanized No-Intro name, generated from the user's old 7z collection — cannot be regenerated). Source of truth is the git-tracked `mygames/title-map.json`, read directly from `~/github/apps/mygames/`; `build_app.sh` bundles a copy into Resources as a fallback for when the repo isn't present (same pattern as mynetworth's 固定収支 md). Unmapped CJK titles get an empty candidate list (placeholder card, no remote lookup). Cache lives in `~/Library/Application Support/MyGames/Thumbnails/` with a `-jp` filename suffix (bump the suffix to invalidate if the preference logic changes).
- The library grid shows ALL scanned ROMs — titles without boxart render a gradient placeholder card with the title text. Do not re-add the old "matched-only" filter.
