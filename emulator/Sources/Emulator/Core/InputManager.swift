import AppKit
import GameController

final class InputManager {
    // 押下状態は 32bit ビットマスク(RETRO_DEVICE_ID_JOYPAD_* は最大 15)。
    // メインスレッド(NSEvent・GameController)が書き、エミュレーションスレッドの
    // input_state コールバックが毎フレーム読むため、ロックで守る
    private var pressedMask: UInt32 = 0
    private let maskLock = NSLock()
    private var keyMonitorDown: Any?
    private var keyMonitorUp: Any?
    private var controllerObservers: [NSObjectProtocol] = []

    /// Esc / ⌘W で呼ばれる(エミュレータ停止用)
    var onStop: (() -> Void)?

    private let keyMap: [UInt16: UInt32] = [
        126: 4,   // ↑  → Up
        125: 5,   // ↓  → Down
        123: 6,   // ←  → Left
        124: 7,   // →  → Right
        6:   8,   // Z  → A
        7:   0,   // X  → B
        0:   9,   // A  → X
        1:   1,   // S  → Y
        36:  3,   // Return → Start
        60:  2,   // Right Shift → Select
        12:  10,  // Q  → L
        13:  11,  // W  → R
    ]

    func isPressed(button: UInt32) -> Bool {
        guard button < 32 else { return false }
        maskLock.lock()
        defer { maskLock.unlock() }
        return pressedMask & (1 << button) != 0
    }

    func start() {
        keyMonitorDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Esc → 停止
                // モニタ自身の解除(stop)を伴うため、ハンドラの外で実行する
                DispatchQueue.main.async { self?.onStop?() }
                return nil
            }
            if event.modifierFlags.contains(.command) {
                if event.keyCode == 13 {  // ⌘W → 停止(標準の「閉じる」より優先)
                    DispatchQueue.main.async { self?.onStop?() }
                    return nil
                }
                // ⌘付きのキーはゲーム入力にせずショートカットとして通す
                return event
            }
            if let btn = self?.keyMap[event.keyCode] {
                self?.setButton(btn, pressed: true)
            }
            return event
        }

        keyMonitorUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if let btn = self?.keyMap[event.keyCode] {
                self?.setButton(btn, pressed: false)
            }
            return event
        }

        setupGameControllers()
    }

    func stop() {
        if let m = keyMonitorDown { NSEvent.removeMonitor(m) }
        if let m = keyMonitorUp { NSEvent.removeMonitor(m) }
        keyMonitorDown = nil
        keyMonitorUp = nil
        controllerObservers.forEach { NotificationCenter.default.removeObserver($0) }
        controllerObservers.removeAll()
        maskLock.lock()
        pressedMask = 0
        maskLock.unlock()
    }

    private func setupGameControllers() {
        let connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.bindController(controller)
        }
        controllerObservers.append(connectObserver)

        for controller in GCController.controllers() {
            bindController(controller)
        }
    }

    private func bindController(_ controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            bindExtendedGamepad(gamepad)
        } else if let gamepad = controller.microGamepad {
            bindMicroGamepad(gamepad)
        }
    }

    private func bindExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        // 十字キーと左スティックは移動に固定(設定対象外)
        let directions: [(GCControllerButtonInput, UInt32)] = [
            (gamepad.dpad.up, 4), (gamepad.dpad.down, 5),
            (gamepad.dpad.left, 6), (gamepad.dpad.right, 7),
            (gamepad.leftThumbstick.up, 4), (gamepad.leftThumbstick.down, 5),
            (gamepad.leftThumbstick.left, 6), (gamepad.leftThumbstick.right, 7),
        ]
        for (element, retroId) in directions {
            element.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.setButton(retroId, pressed: pressed)
            }
        }

        // ボタン類は ControllerConfig の割り当てに従う(設定画面で変更可能)
        let mapping = ControllerConfig.shared.mapping
        let elements: [(String, GCControllerButtonInput?)] = [
            ("buttonA", gamepad.buttonA),
            ("buttonB", gamepad.buttonB),
            ("buttonX", gamepad.buttonX),
            ("buttonY", gamepad.buttonY),
            ("leftShoulder", gamepad.leftShoulder),
            ("rightShoulder", gamepad.rightShoulder),
            ("leftTrigger", gamepad.leftTrigger),
            ("rightTrigger", gamepad.rightTrigger),
            ("buttonMenu", gamepad.buttonMenu),
            ("buttonOptions", gamepad.buttonOptions),
        ]
        for (key, element) in elements {
            guard let element else { continue }
            if let retroId = mapping[key] {
                element.pressedChangedHandler = { [weak self] _, _, pressed in
                    self?.setButton(retroId, pressed: pressed)
                }
            } else {
                element.pressedChangedHandler = nil
            }
        }
    }

    private func bindMicroGamepad(_ gamepad: GCMicroGamepad) {
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(4, pressed: pressed)
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(5, pressed: pressed)
        }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(6, pressed: pressed)
        }
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(7, pressed: pressed)
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(8, pressed: pressed)
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(0, pressed: pressed)
        }
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(3, pressed: pressed)
        }
    }

    private func setButton(_ id: UInt32, pressed: Bool) {
        guard id < 32 else { return }
        maskLock.lock()
        defer { maskLock.unlock() }
        if pressed {
            pressedMask |= (1 << id)
        } else {
            pressedMask &= ~(1 << id)
        }
    }
}
