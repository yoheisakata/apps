// OrientationLock.swift — ボードゲームの「vs CPU は横向き固定・2人対戦は縦向き固定」を
// 実現するための画面回転ロック。SwiftUI単体では画面回転を直接制御できないため、
// AppDelegateの`application(_:supportedInterfaceOrientationsFor:)`をこの値で差し替える。
//
// iPad版のみ(Mac版に画面の向きという概念はない)。BoardGames配下の
// Shared.swift/*Game.swift/*Views.swift はMac版と共有のソースを`#if os(iOS)`で
// 条件コンパイルして使っているため、それらのファイルからこの型を直接参照している。

import SwiftUI
import UIKit

enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .all

    /// 「My Mac (Designed for iPad)」でMacのウィンドウとして動いているときは
    /// 実機の回転という概念がなく、requestGeometryUpdateが逆にウィンドウを
    /// 中途半端な大きさへリサイズしてしまう不具合を起こす(左上にmacOSの
    /// 信号機ボタンが出た「半分のウィンドウ」になる、というユーザー報告で判明)。
    /// 実iPad/シミュレータでは常にfalseなので、そちらの動作には影響しない。
    private static var isRunningAsMacWindow: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
    }

    @MainActor
    static func apply(_ mask: UIInterfaceOrientationMask) {
        // Macのウィンドウとして動いているときはmaskを.allのまま変えない
        // (supportedInterfaceOrientationsForの返り値だけでもウィンドウリサイズの
        // 引き金になり得るため、requestGeometryUpdateを呼ばないだけでは不十分)
        guard !isRunningAsMacWindow else { return }
        self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

final class OrientationAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                      supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
