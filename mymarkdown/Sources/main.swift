import AppKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Overview
//
// MyMarkdown — a live-reloading markdown viewer that doubles as a plain-text
// editor. Files are routed by extension:
//
//   .md / .markdown / .mdown / .mkd  → rendered markdown preview (WKWebView).
//   everything else                  → plain-text editor (the former "mini editor").
//
// One AppController manages a mixed list of windows; each window is either a
// PreviewWindowController (markdown) or an EditorWindowController (text). Both
// conform to the FileWindow protocol so the shared menu can drive either one.
//
// resourcesDirectory / jsStringLiteral / FileWatcher live in
// Sources/AppShared.swift, compiled in alongside this file by build.sh.

// MARK: - Resource loading

func loadTemplate(resources: URL) -> String {
    func read(_ name: String) -> String {
        (try? String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }
    var html = read("template.html")
    // Vendored assets live under Resources/vendor/. mermaid.min.js (~2.5MB) is
    // deliberately NOT inlined: most documents never use it, so the page lazy-
    // loads it from a sibling file only when a ```mermaid``` block exists (see
    // ensureMermaid() in template.html and the staging in AppController).
    let subs: [(String, String)] = [
        ("__GITHUB_MD_CSS__", "vendor/github-markdown.css"),
        ("__HLJS_LIGHT_CSS__", "vendor/github-light.css"),
        ("__HLJS_DARK_CSS__", "vendor/github-dark.css"),
        ("__MARKED_JS__", "vendor/marked.min.js"),
        ("__HLJS_JS__", "vendor/highlight.min.js"),
    ]
    for (token, file) in subs {
        html = html.replacingOccurrences(of: token, with: read(file))
    }
    return html
}

// Markdown extensions get the rendered preview; everything else opens in the editor.
let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
func isMarkdownURL(_ url: URL) -> Bool {
    markdownExtensions.contains(url.pathExtension.lowercased())
}

// MARK: - FileWindow
//
// The common surface both window kinds expose so AppController can manage a
// single mixed list and the menu can drive whichever window is frontmost.
protocol FileWindow: AnyObject {
    var window: NSWindow { get }
    var fileURL: URL? { get }
    var isAuxiliary: Bool { get }
    var dirty: Bool { get set }
    var hasFile: Bool { get }
    func openFile(_ url: URL)
    func reload()
    func save()
    func applyTheme(_ key: String)
}

// MARK: - Drag & drop web view
//
// WKWebView already registers for file-drag types and consumes them, so a
// wrapping NSView never sees the drop. We subclass WKWebView and intercept file
// drags here (routing every dropped file through the app's opener, which decides
// preview vs. editor), deferring everything else (text, links) to WebKit.

func droppableFileURLs(from sender: NSDraggingInfo) -> [URL] {
    let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    guard let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: opts) as? [URL] else { return [] }
    // Folders can't be opened as documents; drop them.
    return urls.filter {
        (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true
    }
}

final class DropWebView: WKWebView {
    // Receives all dropped files at once (so multi-file drops open as tabs).
    var onDrop: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !droppableFileURLs(from: sender).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !droppableFileURLs(from: sender).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if !droppableFileURLs(from: sender).isEmpty { return true }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppableFileURLs(from: sender)
        if !urls.isEmpty {
            onDrop?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }
}

// MARK: - Local image scheme handler
//
// The preview page is a file:// document living in a temp directory, so plain
// relative / file URLs in the markdown (e.g. `images/foo.png` next to the .md)
// can't reach the document's own directory under WebKit's file-origin sandbox.
// We serve those images through a custom `mdv-img:` scheme instead.
final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    weak var controller: PreviewWindowController?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let p = comps.queryItems?.first(where: { $0.name == "p" })?.value,
              !p.isEmpty
        else {
            task.didFailWithError(NSError(domain: "mdv-img", code: 1))
            return
        }

        // Resolve relative paths against the current document's directory; treat
        // a leading-slash path as an absolute filesystem path.
        let fileURL: URL
        if p.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: p).standardizedFileURL
        } else if let base = controller?.fileURL?.deletingLastPathComponent() {
            fileURL = base.appendingPathComponent(p).standardizedFileURL
        } else {
            fileURL = URL(fileURLWithPath: p).standardizedFileURL
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(NSError(domain: "mdv-img", code: 2))
            return
        }

        var mime = "application/octet-stream"
        if let ut = UTType(filenameExtension: fileURL.pathExtension),
           let preferred = ut.preferredMIMEType {
            mime = preferred
        }
        let resp = URLResponse(url: url, mimeType: mime,
                               expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - Preview window (markdown; one per file / tab)

final class PreviewWindowController: NSObject, FileWindow, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    let window: NSWindow
    let webView: DropWebView
    weak var app: AppController?

    var watcher: FileWatcher?
    var fileURL: URL?
    var imageHandler: LocalImageSchemeHandler?
    var templateLoaded = false
    var pendingMarkdown: String?
    var pendingIsWelcome = false
    var rawMode = false
    var dirty = false
    // Set briefly when we write the file ourselves, so the watcher's change
    // event doesn't bounce back and clobber the editor with a reload.
    var ignoreNextChange = false
    // Auxiliary windows (Help) are not reused as the blank "open here" target.
    var isAuxiliary = false

    init(app: AppController, resources: URL, shellURL: URL) {
        self.app = app

        let config = WKWebViewConfiguration()
        // Serve local images referenced by the markdown via a custom scheme.
        let imgHandler = LocalImageSchemeHandler()
        config.setURLSchemeHandler(imgHandler, forURLScheme: "mdv-img")
        let rect = NSRect(x: 0, y: 0, width: 900, height: 1000)
        webView = DropWebView(frame: rect, configuration: config)
        webView.registerForDraggedTypes([.fileURL])
        if #available(macOS 13.3, *) { webView.isInspectable = true }

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // ARC owns the window via the strong `window` property; closing it must
        // NOT also send `-release` (the default for a programmatic NSWindow that
        // isn't managed by an NSWindowController), or the window is over-released
        // and a later autorelease-pool drain crashes on the dangling pointer.
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.contentView = webView
        window.title = "MyMarkdown"

        super.init()

        imageHandler = imgHandler
        imgHandler.controller = self

        config.userContentController.add(self, name: "openExternal")
        config.userContentController.add(self, name: "log")
        config.userContentController.add(self, name: "dirty")
        config.userContentController.add(self, name: "rawmode")
        webView.navigationDelegate = self
        webView.onDrop = { [weak self] urls in self?.app?.openFiles(urls) }
        window.delegate = self

        // Load the shared template shell; markdown is injected via JS afterward.
        webView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())
    }

    func showWelcome() {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        pendingMarkdown = "# MyMarkdown v\(version)\n\n**Drag one or more files onto this window** (multiple files open as tabs), or press **⌘O**.\n\n`.md` files open as a live-reloading preview; any other file opens in the built-in text editor. Press **⌘N** for a new empty document."
        pendingIsWelcome = true
        if templateLoaded { flushPending() }
    }

    // Render fixed markdown content (e.g. the Help page) — no file, no watcher.
    func showContent(title: String, markdown: String) {
        isAuxiliary = true
        window.title = title
        pendingMarkdown = markdown
        pendingIsWelcome = false
        if templateLoaded { flushPending() }
    }

    // Point this window at a file: update title, (re)arm the watcher, render.
    func openFile(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        fileURL = resolved
        window.title = resolved.lastPathComponent
        window.representedURL = resolved
        watcher?.stop()
        dirty = false
        reload()
        watcher = FileWatcher(url: resolved) { [weak self] in self?.fileChangedExternally() }
        watcher?.start()
        app?.noteRecentFile(resolved)
    }

    // Watcher fired. Skip the echo from our own save; otherwise reload.
    private func fileChangedExternally() {
        if ignoreNextChange {
            ignoreNextChange = false
            return
        }
        reload()
    }

    func reload() {
        guard let fileURL = fileURL else { return }
        guard let md = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        dirty = false
        updateDirtyIndicator()
        render(md)
    }

    func render(_ md: String, welcome: Bool = false) {
        guard templateLoaded else {
            pendingMarkdown = md
            pendingIsWelcome = welcome
            return
        }
        let fn = welcome ? "renderWelcome" : "renderMarkdown"
        if #available(macOS 11.0, *) {
            webView.callAsyncJavaScript(
                "window.\(fn)(md);",
                arguments: ["md": md],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        } else {
            let js = "window.\(fn)(\(jsStringLiteral(md)));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func flushPending() {
        // Restore raw-mode state in the freshly-loaded template, then render.
        applyLineNumbers(app?.lineNumbersOn ?? false)
        if rawMode {
            webView.evaluateJavaScript("window.setRawMode(true);", completionHandler: nil)
        }
        if let md = pendingMarkdown {
            pendingMarkdown = nil
            render(md, welcome: pendingIsWelcome)
            pendingIsWelcome = false
        }
    }

    // Push the app-wide theme ("auto" | "light" | "sepia" | "dim" | "dark") into the page.
    func applyTheme(_ theme: String) {
        guard templateLoaded else { return }
        webView.evaluateJavaScript("window.setTheme(\(jsStringLiteral(theme)));", completionHandler: nil)
    }

    // Show/hide the raw-mode line-number gutter.
    func applyLineNumbers(_ on: Bool) {
        guard templateLoaded else { return }
        webView.evaluateJavaScript("window.setLineNumbers(\(on));", completionHandler: nil)
    }

    // Flip between rendered preview and raw markdown source.
    func toggleRaw() {
        rawMode.toggle()
        guard templateLoaded else { return }
        webView.evaluateJavaScript("window.setRawMode(\(rawMode));", completionHandler: nil)
    }

    // Find / Replace bar lives in the page; drive it from the native menu.
    func openFind() {
        guard templateLoaded else { return }
        window.makeKeyAndOrderFront(nil)
        webView.evaluateJavaScript("window.mdvFind && window.mdvFind.open();", completionHandler: nil)
    }

    func findNext() {
        guard templateLoaded else { return }
        webView.evaluateJavaScript("window.mdvFind && window.mdvFind.next();", completionHandler: nil)
    }

    func findPrevious() {
        guard templateLoaded else { return }
        webView.evaluateJavaScript("window.mdvFind && window.mdvFind.prev();", completionHandler: nil)
    }

    // Reflect unsaved edits in the title bar's close button (standard macOS dot).
    func updateDirtyIndicator() {
        window.isDocumentEdited = dirty
    }

    // ⌘S — write the edited source back to the file (only meaningful in raw mode).
    func save() {
        guard let fileURL = fileURL else { NSSound.beep(); return }
        guard templateLoaded else { return }
        webView.evaluateJavaScript("window.getMarkdownSource();") { [weak self] result, _ in
            guard let self = self, let md = result as? String else { return }
            do {
                // Suppress the watcher echo from our own write.
                self.ignoreNextChange = true
                try md.write(to: fileURL, atomically: true, encoding: .utf8)
                self.dirty = false
                self.updateDirtyIndicator()
            } catch {
                self.ignoreNextChange = false
                NSSound.beep()
                FileHandle.standardError.write("save failed: \(error)\n".data(using: .utf8)!)
            }
        }
    }

    var hasFile: Bool { fileURL != nil }

    // WKNavigationDelegate — template finished loading.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        templateLoaded = true
        if let theme = app?.currentTheme { applyTheme(theme) }
        flushPending()
    }

    // JS bridges: log + dirty state + external link clicks.
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "log" {
            FileHandle.standardError.write("[webview] \(message.body)\n".data(using: .utf8)!)
            return
        }
        if message.name == "dirty" {
            dirty = (message.body as? Bool) ?? false
            updateDirtyIndicator()
            return
        }
        if message.name == "rawmode" {
            rawMode = (message.body as? Bool) ?? rawMode
            return
        }
        guard message.name == "openExternal", let href = message.body as? String else { return }
        var resolved: URL?
        if let u = URL(string: href), u.scheme != nil {
            resolved = u
        } else if let base = fileURL?.deletingLastPathComponent() {
            resolved = base.appendingPathComponent(href)
        }
        if let resolved = resolved { NSWorkspace.shared.open(resolved) }
    }

    func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        // WKUserContentController strongly retains its script-message handlers,
        // and self → webView → configuration → userContentController → self
        // closes a retain cycle. Removing the handlers here breaks that cycle so
        // the controller + WKWebView actually deallocate once the tab closes,
        // instead of lingering and receiving stray JS messages. (A deinit can't
        // do this: the cycle keeps self alive, so deinit would never run.)
        let ucc = webView.configuration.userContentController
        for name in ["openExternal", "log", "dirty", "rawmode"] {
            ucc.removeScriptMessageHandler(forName: name)
        }
        app?.windowControllerClosed(self)
    }
}

// MARK: - Theme (text editor)
//
// A color scheme applied to every open editor window. The source of truth is the
// app-wide theme string in UserDefaults ("Theme"); this enum maps that string to
// concrete editor colors. AppController drives updates by re-applying the theme
// to every window when the choice changes.
enum Theme: String, CaseIterable {
    case light, dark, sepia

    var background: NSColor {
        switch self {
        case .light: return NSColor(calibratedWhite: 1.0, alpha: 1)
        case .dark:  return NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        case .sepia: return NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.85, alpha: 1)
        }
    }

    var text: NSColor {
        switch self {
        case .light: return NSColor(calibratedWhite: 0.10, alpha: 1)
        case .dark:  return NSColor(calibratedWhite: 0.88, alpha: 1)
        case .sepia: return NSColor(calibratedRed: 0.36, green: 0.28, blue: 0.21, alpha: 1)
        }
    }

    // Insertion caret + selection highlight.
    var caret: NSColor { text }
    var selection: NSColor {
        switch self {
        case .light: return NSColor.selectedTextBackgroundColor
        case .dark:  return NSColor(calibratedRed: 0.24, green: 0.35, blue: 0.55, alpha: 1)
        case .sepia: return NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.60, alpha: 1)
        }
    }

    // Subtle background for the status bar chrome.
    var chrome: NSColor {
        switch self {
        case .light: return NSColor(calibratedWhite: 0.95, alpha: 1)
        case .dark:  return NSColor(calibratedWhite: 0.16, alpha: 1)
        case .sepia: return NSColor(calibratedRed: 0.91, green: 0.87, blue: 0.77, alpha: 1)
        }
    }

    var secondaryText: NSColor {
        switch self {
        case .light: return NSColor(calibratedWhite: 0.45, alpha: 1)
        case .dark:  return NSColor(calibratedWhite: 0.60, alpha: 1)
        case .sepia: return NSColor(calibratedRed: 0.52, green: 0.44, blue: 0.34, alpha: 1)
        }
    }

    // The window appearance so scrollers / find bar / title bar match.
    var appearance: NSAppearance? {
        switch self {
        case .dark:  return NSAppearance(named: .darkAqua)
        default:     return NSAppearance(named: .aqua)
        }
    }

    // Resolve the app-wide theme string to a concrete editor theme. The preview's
    // extra options collapse: "dim" → dark, "auto" follows the system appearance.
    static var current: Theme {
        let key = UserDefaults.standard.string(forKey: "Theme") ?? "auto"
        switch key {
        case "light": return .light
        case "sepia": return .sepia
        case "dim", "dark": return .dark
        default:
            let dark = NSApp.effectiveAppearance
                .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? .dark : .light
        }
    }
}

// MARK: - Text view
//
// A plain-text NSTextView that intercepts the font panel's changeFont: (which is
// sent to the first responder) so the whole document re-fonts and the choice is
// remembered across launches.
final class EditorTextView: NSTextView {
    weak var owner: EditorViewController?

    override func changeFont(_ sender: Any?) {
        let current = self.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let manager = (sender as? NSFontManager) ?? NSFontManager.shared
        let newFont = manager.convert(current)
        self.font = newFont
        self.textStorage?.font = newFont
        owner?.persistFont(newFont)
    }

    // Accept ⌘= as a synonym for Zoom In (⌘+) so Shift isn't required.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "=" {
            owner?.zoomIn(self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // Pinch-to-zoom on the trackpad adjusts the font size.
    override func magnify(with event: NSEvent) {
        owner?.pinchZoom(by: event.magnification)
    }
}

// MARK: - File drop overlay (text editor)
//
// A transparent view stretched over the whole window content so files can be
// dragged in from Finder to open them. Registers only for file URLs; being the
// frontmost view it receives file drags before the text view does. Text drags
// are untouched (it isn't registered for string types), so they fall through.
final class FileDropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Visual/drop-only: never steal mouse clicks from the editor beneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var highlighted = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlighted else { return }
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.08).setFill()
        bounds.fill()
        accent.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        border.lineWidth = 3
        border.stroke()
    }

    // Dragged file URLs, folders filtered out (a folder can't be opened as text).
    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] }
        highlighted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return highlighted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

// MARK: - Editor view controller

final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    weak var host: EditorWindowController?
    // The file this document is backed by (nil for an untitled document). Set by
    // the window controller; used to decide *.log highlighting.
    var fileURL: URL?

    var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var statusLabel: NSTextField!
    private var statusBar: NSView!
    private var separator: NSBox!

    // Persisted preferences.
    private static let wrapKey = "WrapLines"
    private static let fontNameKey = "EditorFontName"
    private static let fontSizeKey = "EditorFontSize"

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 560))

        // --- Text view + scroll view ---
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let tv = EditorTextView()
        tv.owner = self
        textView = tv
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // Lazy ("non-contiguous") layout: don't lay out the whole document up
        // front — the difference between a large file appearing instantly and
        // the app beachballing while TextKit walks all of it.
        textView.layoutManager?.allowsNonContiguousLayout = true

        scrollView.documentView = textView

        // --- Status bar ---
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.lineBreakMode = .byTruncatingTail

        statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        statusBar.addSubview(statusLabel)

        separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Frontmost, so it sees file drags before the text view; hitTest is nil
        // so it never interferes with clicks or text drags.
        let dropView = FileDropView()
        dropView.translatesAutoresizingMaskIntoConstraints = false
        dropView.onDrop = { [weak self] urls in self?.host?.app?.openFiles(urls) }

        container.addSubview(scrollView)
        container.addSubview(separator)
        container.addSubview(statusBar)
        container.addSubview(dropView)

        NSLayoutConstraint.activate([
            dropView.topAnchor.constraint(equalTo: container.topAnchor),
            dropView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dropView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyFontFromPrefs()
        applyWrapFromPrefs()
        applyTheme(Theme.current)
        // For log documents: recolor edited lines as you type, and track
        // scrolling for the huge-file lazy mode (see log highlighting).
        textView.textStorage?.delegate = self
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollViewportChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The window exists by now, so its appearance can be set.
        applyTheme(Theme.current)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        scrollViewportChanged()
    }

    // MARK: theme

    private var lastAppliedTheme: Theme?

    func applyTheme(_ theme: Theme) {
        guard isViewLoaded else { return }
        // "auto" follows the system, so leave the appearance unset; any explicit
        // choice forces the matching light/dark chrome.
        let rawKey = UserDefaults.standard.string(forKey: "Theme") ?? "auto"
        view.window?.appearance = (rawKey == "auto") ? nil : theme.appearance

        textView.backgroundColor = theme.background
        textView.insertionPointColor = theme.caret
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selection,
            .foregroundColor: theme.text,
        ]

        // Re-coloring existing text is a full-document pass — expensive on large
        // files — so only do it when the theme actually changed.
        if lastAppliedTheme != theme {
            lastAppliedTheme = theme
            textView.textColor = theme.text
            if let storage = textView.textStorage {
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: theme.text,
                                     range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
            }
            // The repaint above wiped any log colors; redo them.
            applyLogHighlightingIfNeeded()
        }

        scrollView.backgroundColor = theme.background
        scrollView.drawsBackground = true

        statusBar.layer?.backgroundColor = theme.chrome.cgColor
        statusLabel.textColor = theme.secondaryText
        separator.isHidden = false
    }

    // MARK: text sync

    func setString(_ s: String) {
        guard isViewLoaded, let tv = textView, let storage = tv.textStorage else { return }
        // Install text, font, and theme color in ONE pass.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: currentFont(),
            .foregroundColor: Theme.current.text,
        ]
        storage.setAttributedString(NSAttributedString(string: s, attributes: attrs))
        tv.typingAttributes = attrs
        applyLogHighlightingIfNeeded()
        updateStatus()
    }

    func textDidChange(_ notification: Notification) {
        host?.markDirty()
        scheduleStatusUpdate()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        scheduleStatusUpdate()
    }

    // Re-evaluate log highlighting after the backing file's extension changes
    // (e.g. an untitled document saved as *.log).
    func fileURLDidChange() {
        applyLogHighlightingIfNeeded()
    }

    // MARK: status bar (line / column, selection, counts)

    private static let wordCountLimit = 1_000_000  // UTF-16 units
    private var statusUpdateWork: DispatchWorkItem?

    private func scheduleStatusUpdate() {
        statusUpdateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateStatus() }
        statusUpdateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func updateStatus() {
        guard let tv = textView else { return }
        let s = tv.string as NSString
        let sel = tv.selectedRange()
        let charCount = s.length

        let before = newlineCount(in: s, range: NSRange(location: 0, length: sel.location))
        let after = newlineCount(in: s, range: NSRange(location: sel.location,
                                                       length: charCount - sel.location))
        let line = before + 1
        let lineCount = before + after + 1

        let prevNL = s.range(of: "\n", options: .backwards,
                             range: NSRange(location: 0, length: sel.location))
        let lineStart = prevNL.location == NSNotFound ? 0 : prevNL.location + 1
        let column = sel.location - lineStart + 1

        var parts = ["Ln \(line), Col \(column)"]
        if sel.length > 0 { parts.append("Sel \(sel.length)") }
        parts.append("\(lineCount) lines")
        if charCount <= Self.wordCountLimit {
            parts.append("\(wordCountOf(tv.string)) words")
        }
        parts.append("\(charCount) chars")
        statusLabel.stringValue = parts.joined(separator: "    ")
    }

    // Count "\n" in `range` by scanning 64K-unichar chunks at memcpy speed.
    private func newlineCount(in s: NSString, range: NSRange) -> Int {
        guard range.length > 0 else { return 0 }
        let chunk = 64 * 1024
        var buffer = [unichar](repeating: 0, count: min(chunk, range.length))
        var count = 0
        var loc = range.location
        let end = range.location + range.length
        buffer.withUnsafeMutableBufferPointer { buf in
            while loc < end {
                let len = min(buf.count, end - loc)
                s.getCharacters(buf.baseAddress!, range: NSRange(location: loc, length: len))
                for i in 0..<len where buf[i] == 10 { count += 1 }
                loc += len
            }
        }
        return count
    }

    private func wordCountOf(_ s: String) -> Int {
        var count = 0
        s.enumerateSubstrings(in: s.startIndex..<s.endIndex,
                              options: [.byWords, .localized]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    // MARK: font

    private func currentFont() -> NSFont {
        let d = UserDefaults.standard
        let size = d.double(forKey: Self.fontSizeKey)
        if let name = d.string(forKey: Self.fontNameKey),
           let f = NSFont(name: name, size: size > 0 ? size : 13) {
            return f
        }
        return NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    private func applyFontFromPrefs() {
        let f = currentFont()
        textView.font = f
        textView.textStorage?.font = f
    }

    fileprivate func persistFont(_ f: NSFont) {
        let d = UserDefaults.standard
        d.set(f.fontName, forKey: Self.fontNameKey)
        d.set(Double(f.pointSize), forKey: Self.fontSizeKey)
    }

    // MARK: zoom (font size)

    private static let minFontSize: CGFloat = 6
    private static let maxFontSize: CGFloat = 96
    private static let defaultFontSize: CGFloat = 13

    private func setFontSize(_ size: CGFloat) {
        let clamped = min(max(size, Self.minFontSize), Self.maxFontSize)
        let base = textView.font ?? currentFont()
        let newFont = NSFontManager.shared.convert(base, toSize: clamped)
        textView.font = newFont
        textView.textStorage?.font = newFont
        persistFont(newFont)
    }

    @objc func zoomIn(_ sender: Any?) {
        let cur = (textView.font ?? currentFont()).pointSize
        setFontSize(cur + 1)
    }

    @objc func zoomOut(_ sender: Any?) {
        let cur = (textView.font ?? currentFont()).pointSize
        setFontSize(cur - 1)
    }

    @objc func actualSize(_ sender: Any?) {
        setFontSize(Self.defaultFontSize)
    }

    func pinchZoom(by magnification: CGFloat) {
        let cur = (textView.font ?? currentFont()).pointSize
        setFontSize(cur * (1 + magnification))
    }

    // MARK: word wrap

    private var wrapEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.wrapKey) as? Bool ?? true
    }

    private func applyWrapFromPrefs() {
        setWrap(wrapEnabled)
    }

    @objc func toggleWrap(_ sender: Any?) {
        setWrap(!wrapEnabled)   // setWrap persists the new value to UserDefaults
    }

    private func setWrap(_ wrap: Bool) {
        guard let container = textView.textContainer else { return }
        UserDefaults.standard.set(wrap, forKey: Self.wrapKey)
        if wrap {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            container.size = NSSize(width: scrollView.contentSize.width,
                                    height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = scrollView.contentSize.width
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
        }
        textView.textContainer?.containerSize = container.size
    }

    func isWrapOn() -> Bool { wrapEnabled }

    // MARK: log highlighting (*.log)

    private enum LogBucket { case error, warn, info, dim }

    private static let logKeywords: [String: LogBucket] = [
        "EMERG": .error, "EMERGENCY": .error, "ALERT": .error, "CRIT": .error,
        "CRITICAL": .error, "FATAL": .error, "ERROR": .error, "ERR": .error,
        "SEVERE": .error, "PANIC": .error,
        "WARN": .warn, "WARNING": .warn,
        "INFO": .info, "NOTICE": .info,
        "DEBUG": .dim, "TRACE": .dim, "VERBOSE": .dim,
        "FINE": .dim, "FINER": .dim, "FINEST": .dim,
    ]

    private static let logHighlightLimit = 10_000_000   // UTF-16 units
    private static let logPrefixScan = 200              // units searched for a level
    private static let logLinesPerSlice = 5000

    private var isLogDocument: Bool {
        fileURL?.pathExtension.lowercased() == "log"
    }

    private var logHighlightGeneration = 0

    private func logColor(_ bucket: LogBucket, theme: Theme) -> NSColor {
        switch bucket {
        case .error: return .systemRed
        case .warn:  return .systemOrange
        case .info:  return .systemBlue
        case .dim:   return theme.secondaryText
        }
    }

    private func isAsciiLetter(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    }

    private func logBucket(forLineIn s: NSString, range: NSRange) -> LogBucket? {
        let scanLen = min(range.length, Self.logPrefixScan)
        guard scanLen > 0 else { return nil }
        var buf = [unichar](repeating: 0, count: scanLen)
        s.getCharacters(&buf, range: NSRange(location: range.location, length: scanLen))
        var i = 0
        while i < scanLen {
            if !isAsciiLetter(buf[i]) { i += 1; continue }
            var token = [unichar]()
            while i < scanLen, isAsciiLetter(buf[i]) {
                let c = buf[i]
                token.append(c >= 97 ? c - 32 : c)  // uppercase ASCII
                i += 1
            }
            if token.count <= 9,
               let bucket = Self.logKeywords[String(utf16CodeUnits: token, count: token.count)] {
                return bucket
            }
        }
        return nil
    }

    private var viewportHighlightingEnabled = false
    private var viewportHighlightWork: DispatchWorkItem?

    private func applyLogHighlightingIfNeeded() {
        logHighlightGeneration += 1
        viewportHighlightingEnabled = false
        guard isLogDocument, let storage = textView.textStorage, storage.length > 0 else { return }
        if storage.length <= Self.logHighlightLimit {
            highlightSlice(from: 0, generation: logHighlightGeneration)
        } else {
            viewportHighlightingEnabled = true
            scheduleViewportHighlight()
        }
    }

    @objc private func scrollViewportChanged() {
        if viewportHighlightingEnabled { scheduleViewportHighlight() }
    }

    private func scheduleViewportHighlight() {
        viewportHighlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.highlightVisibleLines() }
        viewportHighlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func highlightVisibleLines() {
        guard viewportHighlightingEnabled, isLogDocument,
              let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        var rect = textView.visibleRect
        guard rect.height > 0 else { return }
        rect.origin.y -= rect.height
        rect.size.height *= 3
        let glyphs = lm.glyphRange(forBoundingRect: rect, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        highlightLogLines(in: chars)
    }

    private func highlightSlice(from start: Int, generation: Int) {
        guard generation == logHighlightGeneration,
              let storage = textView.textStorage else { return }
        let s = storage.string as NSString
        guard start < s.length else { return }
        let theme = Theme.current
        var loc = start
        var lines = 0
        storage.beginEditing()
        while loc < s.length, lines < Self.logLinesPerSlice {
            let line = s.lineRange(for: NSRange(location: loc, length: 0))
            if let bucket = logBucket(forLineIn: s, range: line) {
                storage.addAttribute(.foregroundColor,
                                     value: logColor(bucket, theme: theme), range: line)
            }
            guard line.length > 0 else { break }
            loc = line.location + line.length
            lines += 1
        }
        storage.endEditing()
        if loc < s.length {
            let next = loc
            DispatchQueue.main.async { [weak self] in
                self?.highlightSlice(from: next, generation: generation)
            }
        }
    }

    private func highlightLogLines(in range: NSRange) {
        guard isLogDocument, let storage = textView.textStorage else { return }
        let s = storage.string as NSString
        guard s.length > 0, range.location <= s.length else { return }
        var r = range
        r.length = min(r.length, s.length - r.location)
        let lines = s.lineRange(for: r)
        let theme = Theme.current
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: theme.text, range: lines)
        var loc = lines.location
        let end = lines.location + lines.length
        while loc < end {
            let line = s.lineRange(for: NSRange(location: loc, length: 0))
            if let bucket = logBucket(forLineIn: s, range: line) {
                storage.addAttribute(.foregroundColor,
                                     value: logColor(bucket, theme: theme), range: line)
            }
            guard line.length > 0 else { break }
            loc = line.location + line.length
        }
        storage.endEditing()
    }

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard isLogDocument,
              editedMask.contains(.editedCharacters),
              editedRange.length <= 50_000 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.highlightLogLines(in: editedRange)
        }
    }
}

// MARK: - Editor window (text; one per file / tab)
//
// Owns the window + EditorViewController and handles file I/O directly (there is
// no NSDocument here — AppController manages the window list uniformly for both
// preview and editor windows). Supports Open / Save / Save As / Revert, dirty
// tracking with a save-on-close prompt, and clean-only external reload.

final class EditorWindowController: NSObject, FileWindow, NSWindowDelegate {
    let window: NSWindow
    let vc: EditorViewController
    weak var app: AppController?

    var fileURL: URL?
    var encoding: String.Encoding = .utf8
    var dirty = false
    let isAuxiliary = false
    var watcher: FileWatcher?
    // Set briefly around our own writes so the watcher's echo doesn't reload.
    var ignoreNextChange = false

    init(app: AppController) {
        self.app = app
        vc = EditorViewController()
        let rect = NSRect(x: 0, y: 0, width: 800, height: 900)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        // ARC owns the window via the strong `window` property; closing it must
        // NOT also send `-release` (the default for a programmatic NSWindow that
        // isn't managed by an NSWindowController), or the window is over-released
        // and a later autorelease-pool drain crashes on the dangling pointer.
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 240)
        window.tabbingMode = .preferred
        window.isRestorable = false
        window.contentViewController = vc
        window.title = "Untitled"
        super.init()
        vc.host = self
        vc.loadViewIfNeeded()   // so setString works before the window is shown
        window.delegate = self
    }

    var hasFile: Bool { fileURL != nil }

    // MARK: encoding

    private func decode(_ data: Data) -> (String, String.Encoding) {
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
        if let s = String(data: data, encoding: .shiftJIS) { return (s, .shiftJIS) }
        if let s = String(data: data, encoding: .isoLatin1) { return (s, .isoLatin1) }
        return (String(decoding: data, as: UTF8.self), .utf8)
    }

    // MARK: opening / new

    func openFile(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: resolved) else { NSSound.beep(); return }
        let (s, enc) = decode(data)
        encoding = enc
        vc.fileURL = resolved
        vc.setString(s)
        dirty = false
        window.isDocumentEdited = false
        window.title = resolved.lastPathComponent
        window.representedURL = resolved
        fileURL = resolved
        armWatcher(on: resolved)
        app?.noteRecentFile(resolved)
    }

    func newUntitled() {
        fileURL = nil
        vc.fileURL = nil
        window.representedURL = nil
        window.title = "Untitled"
        vc.setString("")
        dirty = false
        window.isDocumentEdited = false
    }

    private func armWatcher(on url: URL) {
        watcher?.stop()
        watcher = FileWatcher(url: url) { [weak self] in self?.fileChangedExternally() }
        watcher?.start()
    }

    // Watcher fired. Skip our own write echo; don't clobber unsaved edits.
    private func fileChangedExternally() {
        if ignoreNextChange { ignoreNextChange = false; return }
        if dirty { return }
        reloadFromDisk()
    }

    private func reloadFromDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let (s, enc) = decode(data)
        encoding = enc
        vc.setString(s)
        dirty = false
        window.isDocumentEdited = false
    }

    func markDirty() {
        if !dirty {
            dirty = true
            window.isDocumentEdited = true
        }
    }

    // MARK: saving

    func save() {
        guard let url = fileURL else { saveAs(); return }
        writeToFile(url)
    }

    func saveAs() {
        let panel = NSSavePanel()
        if let f = fileURL {
            panel.directoryURL = f.deletingLastPathComponent()
            panel.nameFieldStringValue = f.lastPathComponent
        } else {
            panel.nameFieldStringValue = "Untitled.txt"
        }
        // runModal (synchronous) so the close-prompt flow can wait on the result.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let extChanged = url.pathExtension.lowercased() != fileURL?.pathExtension.lowercased()
        writeToFile(url)
        let resolved = url.resolvingSymlinksInPath()
        fileURL = resolved
        vc.fileURL = resolved
        window.title = resolved.lastPathComponent
        window.representedURL = resolved
        armWatcher(on: resolved)
        app?.noteRecentFile(resolved)
        if extChanged { vc.fileURLDidChange() }
    }

    private func writeToFile(_ url: URL) {
        let s = vc.textView.string
        guard let data = s.data(using: encoding) ?? s.data(using: .utf8) else {
            NSSound.beep(); return
        }
        do {
            ignoreNextChange = true
            try data.write(to: url, options: .atomic)
            dirty = false
            window.isDocumentEdited = false
        } catch {
            ignoreNextChange = false
            NSSound.beep()
            FileHandle.standardError.write("save failed: \(error)\n".data(using: .utf8)!)
        }
    }

    // File ▸ Reload / Revert. Confirms before discarding unsaved edits.
    func reload() {
        guard fileURL != nil else { return }
        if dirty {
            let alert = NSAlert()
            alert.messageText = "Revert to the last saved version?"
            alert.informativeText = "This document has unsaved changes. Reverting will discard them."
            alert.addButton(withTitle: "Revert")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        reloadFromDisk()
    }

    // MARK: find (drives the standard NSTextView find bar)

    func showFind() { performFind(.showFindInterface) }
    func showFindReplace() { performFind(.showReplaceInterface) }
    func findNext() { performFind(.nextMatch) }
    func findPrevious() { performFind(.previousMatch) }

    private func performFind(_ action: NSTextFinder.Action) {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(vc.textView)
        let item = NSMenuItem()
        item.tag = action.rawValue
        vc.textView.performFindPanelAction(item)
    }

    // MARK: theme

    func applyTheme(_ key: String) {
        // AppController has already written the "Theme" default, so Theme.current
        // resolves to the right editor palette.
        vc.applyTheme(Theme.current)
    }

    // MARK: passthroughs for the menu

    func isWrapOn() -> Bool { vc.isWrapOn() }

    // MARK: window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        let name = fileURL?.lastPathComponent ?? "this document"
        alert.messageText = "Do you want to save the changes you made to \(name)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !dirty   // stay open if the save was cancelled / failed
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        app?.windowControllerClosed(self)
    }
}

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let resources = resourcesDirectory(projectDir: "mymarkdown")
    var shellURL: URL!
    var launched = false
    var pendingOpen: [URL] = []

    // Open windows (each is a tab): a mix of preview and editor controllers.
    var controllers: [FileWindow] = []

    // Recent files (persisted in UserDefaults; most-recent first).
    var recentFiles: [URL] = []
    weak var recentMenu: NSMenu?
    let recentsKey = "RecentFiles"
    let recentsMax = 10

    // Line numbers in the raw markdown source view. Persisted; applies to preview tabs.
    let lineNumbersKey = "LineNumbers"
    var lineNumbersOn = true

    // Theme selection ("auto" follows the system): auto | light | sepia | dim | dark.
    let themeKey = "Theme"
    var currentTheme = "auto"
    let themeChoices: [(title: String, key: String)] = [
        ("System", "auto"), ("Light", "light"), ("Sepia", "sepia"), ("Dim", "dim"), ("Dark", "dark"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        let argURLs = args.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }

        if let img = NSImage(contentsOf: resources.appendingPathComponent("AppIcon.png")) {
            NSApp.applicationIconImage = img
        }

        // Assemble the preview template shell once and reuse it for every preview tab.
        let html = loadTemplate(resources: resources)
        shellURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymarkdown-shell.html")
        try? html.write(to: shellURL, atomically: true, encoding: .utf8)

        // Stage mermaid.min.js next to the shell so the page can lazy-load it.
        let mermaidDst = shellURL.deletingLastPathComponent()
            .appendingPathComponent("mermaid.min.js")
        let mermaidSrc = resources.appendingPathComponent("vendor/mermaid.min.js")
        try? FileManager.default.removeItem(at: mermaidDst)
        try? FileManager.default.copyItem(at: mermaidSrc, to: mermaidDst)

        loadRecentFiles()
        if let saved = UserDefaults.standard.string(forKey: themeKey) { currentTheme = saved }
        if UserDefaults.standard.object(forKey: lineNumbersKey) != nil {
            lineNumbersOn = UserDefaults.standard.bool(forKey: lineNumbersKey)
        }
        setupMenu()
        NSApp.activate(ignoringOtherApps: true)

        launched = true

        let toOpen = !pendingOpen.isEmpty ? pendingOpen : argURLs
        pendingOpen = []
        if toOpen.isEmpty {
            // Empty welcome window (a preview showing the intro text).
            let wc = makePreview()
            wc.showWelcome()
            wc.window.center()
            wc.window.makeKeyAndOrderFront(nil)
        } else {
            openFiles(toOpen)
        }
    }

    // MARK: Window / tab management

    private func makePreview() -> PreviewWindowController {
        let wc = PreviewWindowController(app: self, resources: resources, shellURL: shellURL)
        controllers.append(wc)
        return wc
    }

    private func makeEditor() -> EditorWindowController {
        let wc = EditorWindowController(app: self)
        controllers.append(wc)
        return wc
    }

    // Add a fresh window to the frontmost tab group, or center it if it's the first.
    private func place(_ w: NSWindow) {
        if let host = NSApp.keyWindow ?? controllers.first(where: { $0.window !== w })?.window,
           host !== w {
            host.addTabbedWindow(w, ordered: .above)
        } else {
            w.center()
        }
    }

    func openFile(_ url: URL) { openFiles([url]) }

    // Open files — each becomes its own tab, routed to preview or editor by type.
    func openFiles(_ urls: [URL]) {
        let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !valid.isEmpty else { NSSound.beep(); return }

        for url in valid {
            let wantMarkdown = isMarkdownURL(url)
            // Reuse a blank window of the matching kind (e.g. the launch welcome).
            if let empty = controllers.first(where: {
                $0.fileURL == nil && !$0.isAuxiliary && !$0.dirty &&
                ((wantMarkdown && $0 is PreviewWindowController) ||
                 (!wantMarkdown && $0 is EditorWindowController))
            }) {
                empty.openFile(url)
                empty.window.makeKeyAndOrderFront(nil)
                continue
            }
            let wc: FileWindow = wantMarkdown ? makePreview() : makeEditor()
            wc.openFile(url)
            place(wc.window)
            wc.window.makeKeyAndOrderFront(nil)
        }
        pruneEmptyWindows()
    }

    // Once a real file is open, close any pristine blank windows (the launch
    // welcome preview, or an untouched Untitled) so they don't linger as tabs.
    private func pruneEmptyWindows() {
        guard controllers.contains(where: { $0.hasFile }) else { return }
        for wc in controllers where !wc.hasFile && !wc.isAuxiliary && !wc.dirty {
            wc.window.close()
        }
    }

    func windowControllerClosed(_ wc: FileWindow) {
        controllers.removeAll { $0 === wc }
    }

    // MARK: Recent files

    func loadRecentFiles() {
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        recentFiles = paths.map { URL(fileURLWithPath: $0) }
    }

    func saveRecentFiles() {
        UserDefaults.standard.set(recentFiles.map { $0.path }, forKey: recentsKey)
    }

    func noteRecentFile(_ url: URL) {
        recentFiles.removeAll { $0.path == url.path }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > recentsMax { recentFiles = Array(recentFiles.prefix(recentsMax)) }
        saveRecentFiles()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        rebuildRecentMenu()
    }

    func rebuildRecentMenu() {
        guard let menu = recentMenu else { return }
        menu.removeAllItems()
        if recentFiles.isEmpty {
            let empty = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for url in recentFiles {
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecents(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            openFile(url)
        } else {
            recentFiles.removeAll { $0.path == url.path }
            saveRecentFiles()
            rebuildRecentMenu()
            NSSound.beep()
        }
    }

    @objc func clearRecents(_ sender: Any?) {
        recentFiles.removeAll()
        saveRecentFiles()
        NSDocumentController.shared.clearRecentDocuments(nil)
        rebuildRecentMenu()
    }

    // MARK: File menu actions

    // ⌘N — a new, empty text-editor document.
    @objc func newDocumentFromMenu(_ sender: Any?) {
        let wc = makeEditor()
        wc.newUntitled()
        place(wc.window)
        wc.window.makeKeyAndOrderFront(nil)
        wc.window.makeFirstResponder(wc.vc.textView)
    }

    // ⌘O / menu → file picker (allows multi-select → tabs). Any file type.
    @objc func showOpenPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            if response == .OK, !panel.urls.isEmpty {
                self?.openFiles(panel.urls)
            }
        }
    }

    @objc func reloadFromMenu(_ sender: Any?) {
        frontController()?.reload()
    }

    @objc func saveFromMenu(_ sender: Any?) {
        frontController()?.save()
    }

    @objc func saveAsFromMenu(_ sender: Any?) {
        frontEditor()?.saveAs()
    }

    @objc func revertFromMenu(_ sender: Any?) {
        frontEditor()?.reload()
    }

    // Save every open tab that has unsaved edits and a backing file.
    @objc func saveAllFromMenu(_ sender: Any?) {
        for wc in controllers where wc.hasFile && wc.dirty {
            wc.save()
        }
    }

    // Close every open window/tab. Warns once if any tab has unsaved edits.
    @objc func closeAllFromMenu(_ sender: Any?) {
        let unsaved = controllers.filter { $0.dirty }
        if !unsaved.isEmpty {
            let alert = NSAlert()
            alert.messageText = unsaved.count == 1
                ? "You have unsaved changes in 1 document."
                : "You have unsaved changes in \(unsaved.count) documents."
            alert.informativeText = "Closing all windows will discard those edits. Close anyway?"
            alert.addButton(withTitle: "Close All")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        // Snapshot — closing mutates `controllers` via windowWillClose. Clear
        // dirty first so per-window close prompts are suppressed.
        for wc in controllers { wc.dirty = false }
        for wc in controllers.reversed() { wc.window.close() }
    }

    // Help → MyMarkdown Help. Reuses the open help window if present.
    @objc func openHelp(_ sender: Any?) {
        if let existing = controllers.first(where: { $0.isAuxiliary }) as? PreviewWindowController {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let wc = makePreview()
        wc.showContent(title: "MyMarkdown Help", markdown: helpMarkdown)
        wc.window.center()
        wc.window.makeKeyAndOrderFront(nil)
    }

    var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    var helpMarkdown: String {
        return """
        # MyMarkdown — Help

        A lightweight, live-reloading Markdown viewer and plain-text editor for macOS.

        ## Opening files

        - **Drag & drop** one or more files onto a window. Multiple files open as **tabs**.
        - **File ▸ Open…** (`⌘O`) — pick one or more files of any type.
        - **File ▸ New** (`⌘N`) — a new, empty text document.
        - **File ▸ Open Recent** — jump back to a recently opened file.
        - **Double-click** a file in Finder, or right-click ▸ **Open With ▸ MyMarkdown**.

        `.md` / `.markdown` / `.mdown` / `.mkd` files open as a **rendered preview**;
        every other file opens in the built-in **text editor**.

        ## Markdown preview

        - **Live reload**: edit the file in any editor and save — the preview updates
          automatically, keeping your scroll position.
        - **View ▸ Show Raw Markdown** (`⌘U`) toggles between the rendered preview and
          the editable raw source. In raw mode, **File ▸ Save** (`⌘S`) writes back.
        - **View ▸ Show Line Numbers** (`⌘L`) toggles a gutter in the raw source view.
        - GitHub-flavored Markdown, syntax-highlighted code, and **Mermaid** diagrams
          (` ```mermaid ` fenced blocks). Links open in your browser.

        ## Text editor

        - Standard editing: Undo/Redo, Cut/Copy/Paste, the system **Find** bar (`⌘F`),
          Find & Replace (`⌥⌘F`), and spelling.
        - **File ▸ Save** (`⌘S`) / **Save As…** (`⇧⌘S`) / **Revert to Saved**.
        - **Format ▸ Wrap Lines** and **Format ▸ Show Fonts** (`⌘T`).
        - **View ▸ Zoom In / Out / Actual Size** (`⌘+` / `⌘-` / `⌘0`; pinch to zoom).
        - `.log` files get severity coloring (errors red, warnings orange, info blue).
        - A status bar shows line / column, selection, line / word / character counts.
        - Opening a file that changes on disk reloads it automatically **unless** you
          have unsaved edits.

        ## Tabs

        - Multiple files share one window as tabs (`⌘]` / `⌘[` to switch).
        - Drag a tab out to make it its own window, or drag one in to combine.

        ## Theme

        **View ▸ Theme**: **System** (follow macOS), **Light**, **Sepia**, **Dim**, **Dark**.
        The choice applies to every open tab and is remembered.

        ## Keyboard shortcuts

        | Shortcut | Action |
        |---|---|
        | `⌘N` | New text document |
        | `⌘O` | Open… |
        | `⌘S` | Save |
        | `⇧⌘S` | Save As… |
        | `⌘R` | Reload / Revert current tab |
        | `⌘U` | Toggle raw Markdown (preview) |
        | `⌘L` | Toggle line numbers (preview) |
        | `⌘F` / `⌥⌘F` | Find / Find and Replace |
        | `⌘G` / `⇧⌘G` | Find next / previous |
        | `⌘+` / `⌘-` / `⌘0` | Zoom in / out / actual size (editor) |
        | `⌘Z` / `⇧⌘Z` | Undo / Redo |
        | `⌘]` / `⌘[` | Next / Previous tab |
        | `⌘W` | Close tab |
        | `⇧⌘W` | Close all windows |

        ---

        *MyMarkdown v\(appVersion)*
        """
    }

    // MARK: View menu actions

    @objc func toggleRawFromMenu(_ sender: NSMenuItem) {
        guard let wc = frontPreview() else { return }
        wc.toggleRaw()
        sender.state = wc.rawMode ? .on : .off
    }

    @objc func toggleLineNumbersFromMenu(_ sender: NSMenuItem) {
        lineNumbersOn.toggle()
        UserDefaults.standard.set(lineNumbersOn, forKey: lineNumbersKey)
        for wc in controllers { (wc as? PreviewWindowController)?.applyLineNumbers(lineNumbersOn) }
        sender.state = lineNumbersOn ? .on : .off
    }

    @objc func setThemeFromMenu(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        currentTheme = key
        UserDefaults.standard.set(key, forKey: themeKey)
        for wc in controllers { wc.applyTheme(key) }
    }

    // Editor-only View/Format actions, forwarded to the front editor.
    @objc func zoomInFromMenu(_ sender: Any?) { frontEditor()?.vc.zoomIn(sender) }
    @objc func zoomOutFromMenu(_ sender: Any?) { frontEditor()?.vc.zoomOut(sender) }
    @objc func actualSizeFromMenu(_ sender: Any?) { frontEditor()?.vc.actualSize(sender) }
    @objc func toggleWrapFromMenu(_ sender: Any?) { frontEditor()?.vc.toggleWrap(sender) }

    // MARK: Find (routed by front window kind)

    @objc func findFromMenu(_ sender: Any?) {
        if let p = frontPreview() { p.openFind() }
        else if let e = frontEditor() { e.showFind() }
    }
    @objc func findReplaceFromMenu(_ sender: Any?) {
        if let p = frontPreview() { p.openFind() }
        else if let e = frontEditor() { e.showFindReplace() }
    }
    @objc func findNextFromMenu(_ sender: Any?) {
        if let p = frontPreview() { p.findNext() }
        else if let e = frontEditor() { e.findNext() }
    }
    @objc func findPreviousFromMenu(_ sender: Any?) {
        if let p = frontPreview() { p.findPrevious() }
        else if let e = frontEditor() { e.findPrevious() }
    }

    // MARK: Menu validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let action = item.action
        let front = frontController()
        let isPreview = front is PreviewWindowController
        let isEditor = front is EditorWindowController

        if action == #selector(toggleRawFromMenu(_:)) {
            item.state = ((front as? PreviewWindowController)?.rawMode ?? false) ? .on : .off
            return isPreview
        }
        if action == #selector(toggleLineNumbersFromMenu(_:)) {
            item.state = lineNumbersOn ? .on : .off
            return isPreview
        }
        if action == #selector(setThemeFromMenu(_:)) {
            item.state = (item.representedObject as? String == currentTheme) ? .on : .off
            return true
        }
        if action == #selector(toggleWrapFromMenu(_:)) {
            item.state = ((front as? EditorWindowController)?.isWrapOn() ?? false) ? .on : .off
            return isEditor
        }
        if action == #selector(zoomInFromMenu(_:)) ||
           action == #selector(zoomOutFromMenu(_:)) ||
           action == #selector(actualSizeFromMenu(_:)) {
            return isEditor
        }
        if action == #selector(saveFromMenu(_:)) {
            // Editors can always Save (Save As if untitled); preview needs a file.
            return isEditor || (front?.hasFile ?? false)
        }
        if action == #selector(saveAsFromMenu(_:)) { return isEditor }
        if action == #selector(revertFromMenu(_:)) { return isEditor && (front?.hasFile ?? false) }
        if action == #selector(saveAllFromMenu(_:)) {
            return controllers.contains { $0.hasFile && $0.dirty }
        }
        if action == #selector(reloadFromMenu(_:)) { return front?.hasFile ?? false }
        if action == #selector(closeAllFromMenu(_:)) { return !controllers.isEmpty }
        if action == #selector(findFromMenu(_:)) ||
           action == #selector(findReplaceFromMenu(_:)) ||
           action == #selector(findNextFromMenu(_:)) ||
           action == #selector(findPreviousFromMenu(_:)) {
            return front != nil
        }
        return true
    }

    // MARK: Front-window helpers

    func frontController() -> FileWindow? {
        if let key = NSApp.keyWindow,
           let wc = controllers.first(where: { $0.window === key }) {
            return wc
        }
        return controllers.first
    }

    func frontPreview() -> PreviewWindowController? { frontController() as? PreviewWindowController }
    func frontEditor() -> EditorWindowController? { frontController() as? EditorWindowController }

    // MARK: Menu bar

    func setupMenu() {
        let mainMenu = NSMenu()

        // App menu.
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MyMarkdown",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MyMarkdown",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MyMarkdown",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu.
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        let new = NSMenuItem(title: "New", action: #selector(newDocumentFromMenu(_:)), keyEquivalent: "n")
        new.target = self
        fileMenu.addItem(new)
        let open = NSMenuItem(title: "Open…", action: #selector(showOpenPanel(_:)), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recent = NSMenu(title: "Open Recent")
        recentItem.submenu = recent
        recentMenu = recent
        fileMenu.addItem(recentItem)
        rebuildRecentMenu()

        fileMenu.addItem(.separator())
        let reload = NSMenuItem(title: "Reload / Revert", action: #selector(reloadFromMenu(_:)), keyEquivalent: "r")
        reload.target = self
        fileMenu.addItem(reload)
        let save = NSMenuItem(title: "Save", action: #selector(saveFromMenu(_:)), keyEquivalent: "s")
        save.target = self
        fileMenu.addItem(save)
        let saveAs = NSMenuItem(title: "Save As…", action: #selector(saveAsFromMenu(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        saveAs.target = self
        fileMenu.addItem(saveAs)
        let saveAll = NSMenuItem(title: "Save All", action: #selector(saveAllFromMenu(_:)), keyEquivalent: "")
        saveAll.target = self
        fileMenu.addItem(saveAll)
        let revert = NSMenuItem(title: "Revert to Saved", action: #selector(revertFromMenu(_:)), keyEquivalent: "")
        revert.target = self
        fileMenu.addItem(revert)
        fileMenu.addItem(.separator())
        let close = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(close)
        let closeAll = NSMenuItem(title: "Close All", action: #selector(closeAllFromMenu(_:)), keyEquivalent: "w")
        closeAll.keyEquivalentModifierMask = [.command, .shift]
        closeAll.target = self
        fileMenu.addItem(closeAll)
        fileMenuItem.submenu = fileMenu

        // Edit menu — Undo/Redo/Cut/Copy/Paste/Select All route through the
        // responder chain, so they work in both the raw-markdown web view and
        // the NSTextView editor. Find is routed by AppController.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: Selector(("delete:")), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let find = NSMenuItem(title: "Find…", action: #selector(findFromMenu(_:)), keyEquivalent: "f")
        find.target = self
        editMenu.addItem(find)
        let findReplace = NSMenuItem(title: "Find and Replace…", action: #selector(findReplaceFromMenu(_:)), keyEquivalent: "f")
        findReplace.keyEquivalentModifierMask = [.command, .option]
        findReplace.target = self
        editMenu.addItem(findReplace)
        let findNext = NSMenuItem(title: "Find Next", action: #selector(findNextFromMenu(_:)), keyEquivalent: "g")
        findNext.target = self
        editMenu.addItem(findNext)
        let findPrev = NSMenuItem(title: "Find Previous", action: #selector(findPreviousFromMenu(_:)), keyEquivalent: "g")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        findPrev.target = self
        editMenu.addItem(findPrev)
        editMenu.addItem(.separator())
        // Spelling & grammar (editor; auto-disabled when the preview is front).
        let spellItem = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        let spellMenu = NSMenu(title: "Spelling and Grammar")
        spellItem.submenu = spellMenu
        let showSpell = NSMenuItem(title: "Show Spelling and Grammar",
                                   action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        spellMenu.addItem(showSpell)
        spellMenu.addItem(withTitle: "Check Document Now",
                          action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        spellMenu.addItem(.separator())
        spellMenu.addItem(withTitle: "Check Spelling While Typing",
                          action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
        editMenu.addItem(spellItem)
        editMenuItem.submenu = editMenu

        // Format menu — text-editor specific.
        let formatMenuItem = NSMenuItem()
        mainMenu.addItem(formatMenuItem)
        let formatMenu = NSMenu(title: "Format")
        let showFonts = NSMenuItem(title: "Show Fonts",
                                   action: #selector(NSFontManager.orderFrontFontPanel(_:)), keyEquivalent: "t")
        showFonts.target = NSFontManager.shared
        formatMenu.addItem(showFonts)
        formatMenu.addItem(.separator())
        let wrapItem = NSMenuItem(title: "Wrap Lines",
                                  action: #selector(toggleWrapFromMenu(_:)), keyEquivalent: "")
        wrapItem.target = self
        formatMenu.addItem(wrapItem)
        formatMenuItem.submenu = formatMenu

        // View menu.
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let rawToggle = NSMenuItem(title: "Show Raw Markdown",
                                   action: #selector(toggleRawFromMenu(_:)), keyEquivalent: "u")
        rawToggle.target = self
        viewMenu.addItem(rawToggle)
        let lineNumbersToggle = NSMenuItem(title: "Show Line Numbers",
                                           action: #selector(toggleLineNumbersFromMenu(_:)), keyEquivalent: "l")
        lineNumbersToggle.target = self
        viewMenu.addItem(lineNumbersToggle)
        viewMenu.addItem(.separator())
        // Zoom (editor).
        let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(zoomInFromMenu(_:)), keyEquivalent: "+")
        zoomIn.target = self
        viewMenu.addItem(zoomIn)
        let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(zoomOutFromMenu(_:)), keyEquivalent: "-")
        zoomOut.target = self
        viewMenu.addItem(zoomOut)
        let actualSize = NSMenuItem(title: "Actual Size", action: #selector(actualSizeFromMenu(_:)), keyEquivalent: "0")
        actualSize.target = self
        viewMenu.addItem(actualSize)
        viewMenu.addItem(.separator())
        // Theme submenu.
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        for choice in themeChoices {
            let it = NSMenuItem(title: choice.title,
                                action: #selector(setThemeFromMenu(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = choice.key
            themeMenu.addItem(it)
        }
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)
        viewMenu.addItem(.separator())
        let enterFS = NSMenuItem(title: "Enter Full Screen",
                                 action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        enterFS.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(enterFS)
        viewMenuItem.submenu = viewMenu

        // Window menu — standard tab commands (Show Tab Bar, Move Tab, etc.).
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Show Next Tab", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "]")
        windowMenu.addItem(withTitle: "Show Previous Tab", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "[")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // Help menu.
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        let help = NSMenuItem(title: "MyMarkdown Help",
                              action: #selector(openHelp(_:)), keyEquivalent: "?")
        help.target = self
        helpMenu.addItem(help)
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // Finder: double-click file(s) / drop on app icon / "Open With".
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if launched {
            openFiles(urls)
        } else {
            pendingOpen.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
