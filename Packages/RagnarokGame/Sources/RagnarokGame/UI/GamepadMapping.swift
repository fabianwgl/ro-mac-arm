//
//  GamepadMapping.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import simd

/// A controller button the game reacts to.
///
/// The stick and the d-pad walk, so they are not buttons. The layout is fixed: there is
/// no remapping and no configuration.
enum GamepadButton: Hashable, CaseIterable, Sendable {
    case a
    case b
    case x
    case y
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case menu
}

/// The pure part of controller support: dead zone, vector math and the button layout.
/// `GamepadInput` feeds it the raw controller state, so none of this needs a controller.
///
/// Button layout, using Xbox names (A and B are the bottom and right face buttons):
///
/// - A: attack the selected monster, or else the nearest one
/// - B: close the top window
/// - X, Y, left shoulder, right shoulder, left trigger, right trigger:
///   shortcut row 1, slots 1 to 6
/// - Menu: toggle the options window (the in-game system menu)
/// - Left stick and d-pad: walk
enum GamepadMapping {
    /// Stick deflection below this fraction of full travel is ignored, so a worn stick
    /// resting off-center does not walk the character.
    static let deadZone: Float = 0.25

    /// The longest thumbstick vector, in the points the scene's thumbstick walking expects.
    /// The scene ignores vectors shorter than 15 points; the dead zone stays above that.
    static let thumbstickLength: Float = 100

    /// The action a button triggers when pressed.
    static func action(for button: GamepadButton) -> GameAction {
        switch button {
        case .a: .attack
        case .b: .closeTopWindow
        case .x: .shortcut(row: 0, slot: 0)
        case .y: .shortcut(row: 0, slot: 1)
        case .leftShoulder: .shortcut(row: 0, slot: 2)
        case .rightShoulder: .shortcut(row: 0, slot: 3)
        case .leftTrigger: .shortcut(row: 0, slot: 4)
        case .rightTrigger: .shortcut(row: 0, slot: 5)
        case .menu: .toggleOptions
        }
    }

    /// The buttons which are pressed now but were not before, in a stable order.
    static func newlyPressed(previous: Set<GamepadButton>, current: Set<GamepadButton>) -> [GamepadButton] {
        GamepadButton.allCases.filter { current.contains($0) && !previous.contains($0) }
    }

    /// The thumbstick vector for the controller's left stick and d-pad.
    ///
    /// Both inputs use the controller's axes: x to the right and y up, each from -1 to 1.
    /// The result is in screen space with y down, like the scene's thumbstick. The stick
    /// keeps its analog length (capped at `thumbstickLength`); the d-pad is always full
    /// length. If both are used, the stronger one wins.
    static func movement(stick: SIMD2<Float>, dpad: SIMD2<Float>) -> SIMD2<Float> {
        strongest([thumbstickVector(for: stick), thumbstickVector(for: dpad, isDigital: true)])
    }

    /// The thumbstick vector for the movement keys held down.
    ///
    /// Each direction is a screen direction with y down. Opposite keys cancel, and
    /// diagonals are as long as straight lines.
    static func keyboardMovement(directions: some Sequence<SIMD2<Float>>) -> SIMD2<Float> {
        let sum = directions.reduce(SIMD2<Float>.zero, +)
        return simd_length(sum) > 0 ? simd_normalize(sum) * thumbstickLength : .zero
    }

    /// The one thumbstick value the scene walks with. Whichever of the keyboard and the
    /// controller pushes harder wins, so letting go of one hands walking to the other
    /// instead of stopping it.
    static func walking(keyboard: SIMD2<Float>, gamepad: SIMD2<Float>) -> SIMD2<Float> {
        strongest([keyboard, gamepad])
    }

    /// The longest of the vectors, or the first one when they tie. Zero if there are none.
    static func strongest(_ vectors: some Sequence<SIMD2<Float>>) -> SIMD2<Float> {
        var strongest = SIMD2<Float>.zero
        var strongestLength: Float = 0
        for vector in vectors {
            let length = simd_length(vector)
            if length > strongestLength {
                strongest = vector
                strongestLength = length
            }
        }
        return strongest
    }

    private static func thumbstickVector(for axes: SIMD2<Float>, isDigital: Bool = false) -> SIMD2<Float> {
        let length = simd_length(axes)
        guard length >= deadZone else {
            return .zero
        }

        // The controller's y axis points up, the screen's down.
        let direction = SIMD2<Float>(axes.x, -axes.y) / length
        return direction * (isDigital ? thumbstickLength : min(length, 1) * thumbstickLength)
    }
}
