//
//  GamepadInput.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

#if os(macOS)
import GameController
import simd

/// Reads every connected game controller and reports walking and button actions.
///
/// It only acts while `isActive` is true, which the game window sets from its key state,
/// so a controller does nothing while another window or app has focus. Becoming inactive
/// drops walking at once; buttons already held when it becomes active again do not fire.
/// The layout lives in `GamepadMapping`.
@MainActor
final class GamepadInput {
    /// Runs when the walking vector changes: screen space, y down, up to 100 long.
    var onMovementChange: (SIMD2<Float>) -> Void = { _ in }

    /// Runs when a mapped button is pressed.
    var onAction: (GameAction) -> Void = { _ in }

    /// The walking vector from the controllers, zero while inactive.
    private(set) var movement: SIMD2<Float> = .zero

    var isActive = false {
        didSet {
            guard isActive != oldValue else {
                return
            }
            if isActive {
                // Whatever is held at this moment is the starting point, not a press.
                let state = Self.state(of: Self.gamepads())
                pressedButtons = state.pressedButtons
                setMovement(state.movement)
            } else {
                pressedButtons = []
                setMovement(.zero)
            }
        }
    }

    private var pressedButtons: Set<GamepadButton> = []
    private var observers: [any NSObjectProtocol] = []

    /// Starts listening for controllers. Call `stop()` before releasing this object.
    func start() {
        guard observers.isEmpty else {
            return
        }

        // Controller input arrives only while the app is active. This is the default.
        GCController.shouldMonitorBackgroundEvents = false

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.observeConnectedControllers()
                    self?.refresh()
                }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] notification in
                let disconnected = (notification.object as? GCController).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    // The controller may still be listed while this runs. Its held stick
                    // and buttons are dropped either way.
                    self?.refresh(excluding: disconnected)
                }
            },
        ]

        observeConnectedControllers()
        refresh()
    }

    /// Stops listening and drops everything held.
    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []

        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }

        isActive = false
    }

    private func observeConnectedControllers() {
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
    }

    /// Reads all controllers again, so a second controller cannot cancel the first.
    private func refresh(excluding excludedController: ObjectIdentifier? = nil) {
        guard isActive else {
            return
        }

        let state = Self.state(of: Self.gamepads(excluding: excludedController))
        let presses = GamepadMapping.newlyPressed(previous: pressedButtons, current: state.pressedButtons)
        pressedButtons = state.pressedButtons
        setMovement(state.movement)

        for button in presses {
            onAction(GamepadMapping.action(for: button))
        }
    }

    private func setMovement(_ newValue: SIMD2<Float>) {
        guard newValue != movement else {
            return
        }
        movement = newValue
        onMovementChange(newValue)
    }

    private static func gamepads(excluding excludedController: ObjectIdentifier? = nil) -> [GCExtendedGamepad] {
        GCController.controllers()
            .filter { ObjectIdentifier($0) != excludedController }
            .compactMap(\.extendedGamepad)
    }

    private static func state(of gamepads: [GCExtendedGamepad]) -> (movement: SIMD2<Float>, pressedButtons: Set<GamepadButton>) {
        let movement = GamepadMapping.strongest(gamepads.map { gamepad in
            GamepadMapping.movement(
                stick: SIMD2(gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value),
                dpad: SIMD2(gamepad.dpad.xAxis.value, gamepad.dpad.yAxis.value)
            )
        })

        var pressedButtons: Set<GamepadButton> = []
        for gamepad in gamepads {
            let buttons: [(GCControllerButtonInput, GamepadButton)] = [
                (gamepad.buttonA, .a),
                (gamepad.buttonB, .b),
                (gamepad.buttonX, .x),
                (gamepad.buttonY, .y),
                (gamepad.leftShoulder, .leftShoulder),
                (gamepad.rightShoulder, .rightShoulder),
                (gamepad.leftTrigger, .leftTrigger),
                (gamepad.rightTrigger, .rightTrigger),
                (gamepad.buttonMenu, .menu),
            ]
            for (input, button) in buttons where input.isPressed {
                pressedButtons.insert(button)
            }
        }

        return (movement, pressedButtons)
    }
}
#endif
