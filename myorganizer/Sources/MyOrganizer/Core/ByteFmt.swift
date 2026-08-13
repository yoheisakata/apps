import Foundation

/// バイト数を人間が読みやすい文字列に整形するヘルパー。
enum ByteFmt {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
