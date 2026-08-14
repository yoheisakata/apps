import AppKit

// AppShared.swift — small AppKit utilities compiled into mymarkdown alongside
// Sources/main.swift: FileWatcher (debounced file-change watching for live
// reload), resourcesDirectory(projectDir:), and jsStringLiteral.

// MARK: - Resource loading
//
// Resources live next to the executable in `Resources/` (when run via the .app
// bundle) or at the repo path during dev runs. `projectDir` is the app's folder
// name in this repo, used for the cwd-relative dev fallback.

func resourcesDirectory(projectDir: String) -> URL {
    let fm = FileManager.default
    let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()

    // Candidate locations, in priority order.
    let candidates = [
        exeDir.appendingPathComponent("Resources"),                       // alongside binary
        exeDir.deletingLastPathComponent().appendingPathComponent("Resources"),
        URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources"),
        URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("\(projectDir)/Resources"),
    ]
    for c in candidates {
        if fm.fileExists(atPath: c.appendingPathComponent("template.html").path) {
            return c
        }
    }
    // Fall back to alongside the binary even if missing — error surfaces later.
    return exeDir.appendingPathComponent("Resources")
}

// MARK: - JS string literal escaping
//
// Used only on the pre-macOS-11 fallback paths; modern paths pass values as
// real arguments via callAsyncJavaScript instead of building giant literals.

func jsStringLiteral(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{2028}": out += "\\u2028"   // line separator — breaks JS strings
        case "\u{2029}": out += "\\u2029"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    out += "\""
    return out
}

// MARK: - File watcher
//
// Watches one file for changes. A DispatchSource on the open descriptor gives
// instant events; the mtime poll only runs while the descriptor cannot be
// armed (file briefly missing during an atomic save, or gone), instead of
// ticking forever alongside a healthy event source. Change bursts (the source
// event + the re-arm echo + a poll hit from the same save) are coalesced into
// a single onChange via a short debounce, so one save triggers one re-render.

final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pollTimer: DispatchSourceTimer?
    private var lastMTime: Date?
    private var pending: DispatchWorkItem?
    private var stopped = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        stopped = false
        arm()
    }

    // Debounce: multiple raw events from one save collapse into one callback.
    private func fireChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.stopped else { return }
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func currentMTime() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    private func arm() {
        cancelSource()
        let newFD = open(url.path, O_EVTONLY)
        guard newFD >= 0 else {
            // Can't watch right now (file missing / mid-replace) — poll until
            // the file is back, then hop onto the event source again.
            fd = -1
            startPolling()
            return
        }
        fd = newFD
        stopPolling()   // event source is live; no need for timer wakeups
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: newFD,
            eventMask: [.write, .extend, .delete, .rename, .link],
            queue: .main
        )
        self.source = src
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = src.data
            self.fireChange()
            // Inode was replaced (atomic save) — re-arm on the new file.
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self = self, !self.stopped else { return }
                    self.arm()
                    // The new inode may have been written after the event we
                    // saw; fire again (debounced) so the final content wins.
                    self.fireChange()
                }
            }
        }
        // Close exactly the descriptor THIS source owns. Capturing `newFD` by
        // value (not reading self.fd later) is essential: the cancel handler
        // runs asynchronously, by which point a re-arm may have already stored
        // a different, live fd in self.fd — closing that would pull the rug out
        // from under the new source and hand a reused fd number to two owners.
        src.setCancelHandler {
            close(newFD)
        }
        src.resume()
        lastMTime = currentMTime()
    }

    // Poll fallback, active only while the descriptor can't be armed.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.stopped else { return }
            if let m = self.currentMTime(), m != self.lastMTime {
                self.lastMTime = m
                self.fireChange()
            }
            // Try to get back onto the event source (stops this poll on success).
            self.arm()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func cancelSource() {
        source?.cancel()
        source = nil
    }

    func stop() {
        stopped = true
        pending?.cancel()
        pending = nil
        cancelSource()
        stopPolling()
    }
}
