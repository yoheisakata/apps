import SwiftUI
import AppKit

/// フォーカス時に必ず英数入力(ローマ字入力ソース)へ切り替わる SecureField。
///
/// SwiftUI 標準の SecureField は、日本語 IME が全角のままだとパスワード(半角英数記号)を
/// 直接打てず、変換・確定が挟まって入力できない。フィールドエディタの
/// `allowedInputSourceLocales` をローマ字のみに制限すると、このフィールドにフォーカスした
/// 瞬間に自動で英数へ切り替わり、IME の状態に関係なく半角で入力できる。
struct RomanSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> RomanNSSecureTextField {
        let field = RomanNSSecureTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.focusRingType = .default
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: RomanNSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: RomanSecureField
        init(_ parent: RomanSecureField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// フォーカスを得たときにフィールドエディタをローマ字入力に制限する NSSecureTextField。
final class RomanNSSecureTextField: NSSecureTextField {
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, let editor = currentEditor() as? NSTextView {
            editor.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        }
        return became
    }
}

/// RomanSecureField の平文版。パスワード表示トグルで「見せる」ときに使う。
/// マスクしない以外は RomanSecureField と同じで、フォーカス時に英数入力へ固定する。
struct RomanTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> RomanNSTextField {
        let field = RomanNSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.focusRingType = .default
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: RomanNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: RomanTextField
        init(_ parent: RomanTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// フォーカス時にローマ字入力へ固定する通常の NSTextField。
final class RomanNSTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, let editor = currentEditor() as? NSTextView {
            editor.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        }
        return became
    }
}
