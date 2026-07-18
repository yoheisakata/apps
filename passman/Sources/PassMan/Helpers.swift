import AppKit

enum ClipboardManager {
    private static var pendingClear: DispatchWorkItem?

    static func copy(_ text: String, clearAfter seconds: Int? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        pendingClear?.cancel()
        guard let seconds else { return }
        let changeCount = pasteboard.changeCount
        let workItem = DispatchWorkItem {
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
        pendingClear = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: workItem)
    }
}
