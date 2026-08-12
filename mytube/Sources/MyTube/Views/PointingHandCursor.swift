import AppKit
import SwiftUI

/// ホバー中はカーソルを指差し(`NSCursor.pointingHand`)に変える(2026-08-05、
/// 「サムネイル/動画をクリックできる場所にきたらカーソルを手のマークにしてほしい。
/// YouTubeのように」という要望への対応)。
///
/// **`.onHover` + `NSCursor.push()`/`pop()`ではなく、`NSView.resetCursorRects()`を
/// オーバーライドする方式**(2026-08-05、当初は`.onHover`ベースで実装していたが
/// 「グリッドモードで指差しにならない」という報告で撤回・作り直した)。`VideoTableView`
/// (`Table`のセル、`Button`の外)では`.onHover`方式でも問題なく動いたが、`VideoCardView`
/// (`Button`で丸ごと囲んでいるカード)では動かなかった ― SwiftUIの`Button`は独自に
/// マウスカーソルの管理を行っており、`.onHover`内で`NSCursor.push()`しても`Button`側の
/// カーソル制御に上書きされてしまうとみられる(push/popのペア自体は正しく呼べていても、
/// 実際に見た目のカーソルには反映されない)。AppKit本来のカーソル矩形システム
/// (`NSView.addCursorRect(_:cursor:)`、ウィンドウがマウス移動のたびに参照する、
/// クリックのヒットテストとは独立した仕組み)に直接登録する方式に切り替えることで、
/// `Button`の内側かどうかに関わらず確実に効くようにした。
private final class PointingHandCursorNSView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// `PointingHandCursorNSView`をSwiftUIから使うためのラッパー。対象のビューに
/// `.overlay(...)`で重ねる ― クリックそのものは奪わないよう`allowsHitTesting(false)`を
/// `pointingHandOnHover()`側で付ける。
private struct PointingHandCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PointingHandCursorNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func pointingHandOnHover() -> some View {
        overlay(PointingHandCursorArea().allowsHitTesting(false))
    }
}
