import AppKit
import GameController

final class InputManager {
    private var pressedButtons: Set<UInt32> = []
    private var keyMonitorDown: Any?
    private var keyMonitorUp: Any?
    private var controllerObservers: [NSObjectProtocol] = []

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
        pressedButtons.contains(button)
    }

    func start() {
        keyMonitorDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let btn = self?.keyMap[event.keyCode] {
                self?.pressedButtons.insert(btn)
            }
            return event
        }

        keyMonitorUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if let btn = self?.keyMap[event.keyCode] {
                self?.pressedButtons.remove(btn)
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
        pressedButtons.removeAll()
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
            self?.setButton(8, pressed: pressed)  // A
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(0, pressed: pressed)  // B
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(9, pressed: pressed)  // X
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(1, pressed: pressed)  // Y
        }
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(10, pressed: pressed) // L
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(11, pressed: pressed) // R
        }
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(3, pressed: pressed)  // Start
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(2, pressed: pressed)  // Select
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
        if pressed {
            pressedButtons.insert(id)
        } else {
            pressedButtons.remove(id)
        }
    }
}
