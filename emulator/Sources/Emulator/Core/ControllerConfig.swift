import Foundation
import GameController

/// libretro RETRO_DEVICE_ID_JOYPAD_* に対応する仮想ボタン
enum RetroButton: UInt32, CaseIterable, Identifiable {
    case b = 0
    case y = 1
    case select = 2
    case start = 3
    case a = 8
    case x = 9
    case l = 10
    case r = 11

    var id: UInt32 { rawValue }

    var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .l: return "L"
        case .r: return "R"
        case .start: return "Start"
        case .select: return "Select"
        }
    }

    /// 設定画面での表示順
    static let displayOrder: [RetroButton] = [.a, .b, .x, .y, .l, .r, .start, .select]
}

/// USB/Bluetooth コントローラーの接続監視とボタン割り当て(物理ボタン → 仮想ボタン)。
/// 割り当ては UserDefaults に保存され、ゲーム起動時に InputManager が読み込む。
final class ControllerConfig: ObservableObject {
    static let shared = ControllerConfig()

    /// 物理ボタンの識別キーと表示名
    static let physicalButtons: [(key: String, label: String)] = [
        ("buttonA", "Aボタン"),
        ("buttonB", "Bボタン"),
        ("buttonX", "Xボタン"),
        ("buttonY", "Yボタン"),
        ("leftShoulder", "L1"),
        ("rightShoulder", "R1"),
        ("leftTrigger", "L2"),
        ("rightTrigger", "R2"),
        ("buttonMenu", "Menu"),
        ("buttonOptions", "Options"),
    ]

    static let defaultMapping: [String: UInt32] = [
        "buttonA": RetroButton.a.rawValue,
        "buttonB": RetroButton.b.rawValue,
        "buttonX": RetroButton.x.rawValue,
        "buttonY": RetroButton.y.rawValue,
        "leftShoulder": RetroButton.l.rawValue,
        "rightShoulder": RetroButton.r.rawValue,
        "buttonMenu": RetroButton.start.rawValue,
        "buttonOptions": RetroButton.select.rawValue,
    ]

    @Published var mapping: [String: UInt32] {
        didSet { save() }
    }
    @Published private(set) var controllers: [GCController] = []
    /// 割り当て待ち中の仮想ボタン(設定画面の「変更…」で入る)
    @Published var capturingFor: UInt32?

    private let defaultsKey = "controllerMapping"
    private var observers: [NSObjectProtocol] = []

    private init() {
        if let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] {
            mapping = dict.mapValues { UInt32($0) }
        } else {
            mapping = Self.defaultMapping
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() })

        refresh()
    }

    func reset() {
        mapping = Self.defaultMapping
    }

    /// 仮想ボタンに割り当てられている物理ボタンの表示名
    func physicalLabel(for retroId: UInt32) -> String {
        guard let key = mapping.first(where: { $0.value == retroId })?.key else {
            return "未割り当て"
        }
        return Self.physicalButtons.first(where: { $0.key == key })?.label ?? key
    }

    private func save() {
        UserDefaults.standard.set(mapping.mapValues { Int($0) }, forKey: defaultsKey)
    }

    private func refresh() {
        controllers = GCController.controllers()
        for controller in controllers {
            installCaptureHandler(controller)
        }
    }

    /// 「押して割り当て」用の監視。InputManager は各ボタンの pressedChangedHandler を
    /// 使うため、プロファイル全体の valueChangedHandler とは競合しない。
    private func installCaptureHandler(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] pad, element in
            guard let self, let target = self.capturingFor else { return }
            guard let key = Self.physKey(for: element, in: pad),
                  let button = element as? GCControllerButtonInput, button.isPressed else { return }
            DispatchQueue.main.async {
                var m = self.mapping
                // 1つの仮想ボタンには物理ボタン1つだけ割り当てる
                for (k, v) in m where v == target {
                    m.removeValue(forKey: k)
                }
                m[key] = target
                self.mapping = m
                self.capturingFor = nil
            }
        }
    }

    static func physKey(for element: GCControllerElement, in pad: GCExtendedGamepad) -> String? {
        if element === pad.buttonA { return "buttonA" }
        if element === pad.buttonB { return "buttonB" }
        if element === pad.buttonX { return "buttonX" }
        if element === pad.buttonY { return "buttonY" }
        if element === pad.leftShoulder { return "leftShoulder" }
        if element === pad.rightShoulder { return "rightShoulder" }
        if element === pad.leftTrigger { return "leftTrigger" }
        if element === pad.rightTrigger { return "rightTrigger" }
        if element === pad.buttonMenu { return "buttonMenu" }
        if let options = pad.buttonOptions, element === options { return "buttonOptions" }
        return nil
    }
}
