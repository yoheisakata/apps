import SwiftUI
import AppKit

struct EmulatorView: NSViewRepresentable {
    let frame: CGImage?

    func makeNSView(context: Context) -> EmulatorNSView {
        let view = EmulatorNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .black
        view.layer?.magnificationFilter = .nearest
        view.layer?.contentsGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: EmulatorNSView, context: Context) {
        nsView.layer?.contents = frame
    }
}

class EmulatorNSView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        // Swallow to prevent beep; InputManager handles via NSEvent monitor
    }

    override func keyUp(with event: NSEvent) {}
}
