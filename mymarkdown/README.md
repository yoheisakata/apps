# MyMarkdown

A native macOS markdown viewer **and plain-text editor** with **live reload**.
Files are routed by extension:

- **`.md` / `.markdown` / `.mdown` / `.mkd`** → rendered markdown **preview**.
  Edit the file in any editor; when you save, the preview updates automatically —
  keeping your scroll position.
- **Everything else** → the built-in **text editor** (the former standalone
  "mini editor", merged in here): Save / Save As / Revert, the system Find bar,
  Find & Replace (`⌥⌘F`), fonts, zoom, word wrap, a line/word/char status bar,
  and `.log` severity coloring (errors red, warnings orange, info blue).

Common features across both:

- Native Swift + AppKit + `WKWebView` (no browser, no Node, no runtime network).
- Preview rendering by [marked](https://marked.js.org/) + GitHub markdown CSS +
  [highlight.js](https://highlightjs.org/) for code blocks (all vendored under
  `Resources/vendor/`); Mermaid diagrams lazy-load from a sibling file.
- Theme selectable from **View ▸ Theme**: System (follows the system
  appearance), Light, Sepia (warm paper), Dim (a mid-contrast dark), or Dark.
  Applies to preview and editor tabs alike; remembered across launches.
- Multiple files open as tabs; **⌘N** opens a new empty text document.
- Links (in previews) open in your default browser instead of navigating.

## Install

Build once and install into `/Applications/MyApplications`:

```bash
cd mymarkdown
./build.sh           # = ./build.sh install — build + copy to /Applications/MyApplications
```

Then launch from **Spotlight** (⌘Space → "MyMarkdown"), **Launchpad**, or
the **Applications** folder. You only re-run this when the **source changes**;
the app is ad-hoc codesigned for local use.

Other `build.sh` commands:

```bash
./build.sh app       # build + open build/MyMarkdown.app in place (no install)
./build.sh build     # compile the raw binary only
./build.sh clean     # remove build/
```

## Usage

Once the app is open:

- **Drag & drop** any file onto the window (folders are ignored).
- **⌘O** (or File → Open…) to pick one or more files of any type.
- **⌘N** for a new, empty text document.
- Right-click a file in Finder → **Open With → MyMarkdown**.

Markdown files open as a live-reloading preview; other files open in the text
editor. Multiple files open as tabs. For a markdown file, edit it in your editor
of choice and save — the preview refreshes on its own, keeping your scroll
position (or toggle raw mode with `⌘U` and edit + save right in the window).

## How live reload works

Two mechanisms, for robustness against different editors' save patterns:

1. A `DispatchSource` file-system watcher on the file descriptor (instant
   `write`/`extend`/`rename`/`delete` events).
2. A 0.5s mtime poll as a fallback, which also re-arms the watcher when an
   editor saves atomically (write-to-temp + rename replaces the inode, which
   invalidates the original descriptor).

On each change the raw markdown is re-injected into the page via
`evaluateJavaScript`, and the scroll **ratio** is preserved so position survives
even when the document length changes.

## Layout

```
mymarkdown/
├── build.sh                   # build / install the GUI app
├── Sources/
│   ├── main.swift             # app, windows, menus, editor + preview controllers
│   └── AppShared.swift        # FileWatcher, resource loading, JS string escaping
└── Resources/
    ├── template.html          # shell page; tokens replaced at load with vendored assets
    └── vendor/                # marked, highlight.js, github-markdown CSS, hljs themes
```

## Requirements

macOS with the Swift toolchain (`swiftc`) — Xcode Command Line Tools is enough.
Built and tested on macOS 26 / arm64, Swift 6.3.
