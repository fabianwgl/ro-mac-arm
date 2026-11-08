//
//  GamepadMappingTests.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import simd
import Testing
@testable import RagnarokGame

struct GamepadMappingTests {
    private func expectEqual(_ actual: SIMD2<Float>, _ expected: SIMD2<Float>, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(simd_distance(actual, expected) < 0.001, "\(actual) is not \(expected)", sourceLocation: sourceLocation)
    }

    // MARK: Stick and d-pad

    @Test func stickInsideTheDeadZoneDoesNotWalk() {
        expectEqual(GamepadMapping.movement(stick: .zero, dpad: .zero), .zero)
        expectEqual(GamepadMapping.movement(stick: SIMD2(0.1, 0.1), dpad: .zero), .zero)
        expectEqual(GamepadMapping.movement(stick: SIMD2(0.24, 0), dpad: .zero), .zero)
        expectEqual(GamepadMapping.movement(stick: SIMD2(0, -0.24), dpad: .zero), .zero)
    }

    @Test func stickJustOutsideTheDeadZoneWalksAboveTheSceneThreshold() {
        let movement = GamepadMapping.movement(stick: SIMD2(0.26, 0), dpad: .zero)

        // The scene ignores thumbstick vectors of 15 points or fewer.
        #expect(simd_length(movement) > 15)
        expectEqual(movement, SIMD2(26, 0))
    }

    @Test func stickKeepsItsAnalogLength() {
        expectEqual(GamepadMapping.movement(stick: SIMD2(0.5, 0), dpad: .zero), SIMD2(50, 0))
        expectEqual(GamepadMapping.movement(stick: SIMD2(-0.75, 0), dpad: .zero), SIMD2(-75, 0))
    }

    @Test func stickPointingUpWalksTowardTheTopOfTheScreen() {
        // The controller's y axis points up. The scene's thumbstick has y pointing down.
        expectEqual(GamepadMapping.movement(stick: SIMD2(0, 1), dpad: .zero), SIMD2(0, -100))
        expectEqual(GamepadMapping.movement(stick: SIMD2(0, -1), dpad: .zero), SIMD2(0, 100))
        expectEqual(GamepadMapping.movement(stick: SIMD2(1, 0), dpad: .zero), SIMD2(100, 0))
        expectEqual(GamepadMapping.movement(stick: SIMD2(-1, 0), dpad: .zero), SIMD2(-100, 0))
    }

    @Test func stickCornerIsCappedLikeTheKeyboard() {
        // The square stick range reaches (1, 1), which is longer than a full push.
        let movement = GamepadMapping.movement(stick: SIMD2(1, 1), dpad: .zero)

        #expect(abs(simd_length(movement) - GamepadMapping.thumbstickLength) < 0.001)
        expectEqual(movement, SIMD2(70.7107, -70.7107))
    }

    @Test func dpadIsAlwaysFullLength() {
        expectEqual(GamepadMapping.movement(stick: .zero, dpad: SIMD2(1, 0)), SIMD2(100, 0))
        expectEqual(GamepadMapping.movement(stick: .zero, dpad: SIMD2(0, 1)), SIMD2(0, -100))
        expectEqual(GamepadMapping.movement(stick: .zero, dpad: SIMD2(0, -1)), SIMD2(0, 100))
    }

    @Test func dpadDiagonalIsAsLongAsAStraightLine() {
        let movement = GamepadMapping.movement(stick: .zero, dpad: SIMD2(-1, 1))

        #expect(abs(simd_length(movement) - GamepadMapping.thumbstickLength) < 0.001)
        expectEqual(movement, SIMD2(-70.7107, -70.7107))
    }

    @Test func strongerOfStickAndDpadWins() {
        // A half push of the stick loses to the d-pad.
        expectEqual(GamepadMapping.movement(stick: SIMD2(-0.5, 0), dpad: SIMD2(1, 0)), SIMD2(100, 0))
        // A stick inside the dead zone does not fight the d-pad.
        expectEqual(GamepadMapping.movement(stick: SIMD2(0.1, 0), dpad: SIMD2(0, 1)), SIMD2(0, -100))
        // A full push of the stick ties the d-pad, and the stick comes first.
        expectEqual(GamepadMapping.movement(stick: SIMD2(-1, 0), dpad: SIMD2(1, 0)), SIMD2(-100, 0))
    }

    // MARK: Keyboard

    private let up = SIMD2<Float>(0, -1)
    private let down = SIMD2<Float>(0, 1)
    private let left = SIMD2<Float>(-1, 0)
    private let right = SIMD2<Float>(1, 0)

    @Test func keyboardMovement() {
        expectEqual(GamepadMapping.keyboardMovement(directions: []), .zero)
        expectEqual(GamepadMapping.keyboardMovement(directions: [up]), SIMD2(0, -100))
        expectEqual(GamepadMapping.keyboardMovement(directions: [up, right]), SIMD2(70.7107, -70.7107))
        expectEqual(GamepadMapping.keyboardMovement(directions: [up, down]), .zero)
        expectEqual(GamepadMapping.keyboardMovement(directions: [left, right, down]), SIMD2(0, 100))
    }

    // MARK: Keyboard and controller together

    @Test func walkingFollowsWhicheverInputIsHeld() {
        let keyboard = GamepadMapping.keyboardMovement(directions: [up])
        let stick = GamepadMapping.movement(stick: SIMD2(1, 0), dpad: .zero)

        expectEqual(GamepadMapping.walking(keyboard: .zero, gamepad: .zero), .zero)
        expectEqual(GamepadMapping.walking(keyboard: keyboard, gamepad: .zero), SIMD2(0, -100))
        expectEqual(GamepadMapping.walking(keyboard: .zero, gamepad: stick), SIMD2(100, 0))
    }

    @Test func releasingOneInputHandsWalkingToTheOther() {
        let keyboard = GamepadMapping.keyboardMovement(directions: [left])
        let halfStick = GamepadMapping.movement(stick: SIMD2(0.5, 0), dpad: .zero)

        // Both held: the keyboard is full length, so it wins over a half push.
        expectEqual(GamepadMapping.walking(keyboard: keyboard, gamepad: halfStick), SIMD2(-100, 0))
        // The keyboard is released: the stick keeps walking.
        expectEqual(GamepadMapping.walking(keyboard: .zero, gamepad: halfStick), SIMD2(50, 0))
        // The stick is released instead: the keyboard keeps walking.
        expectEqual(GamepadMapping.walking(keyboard: keyboard, gamepad: .zero), SIMD2(-100, 0))
    }

    @Test func opposingInputsDoNotCancelEachOther() {
        let keyboard = GamepadMapping.keyboardMovement(directions: [left])
        let dpad = GamepadMapping.movement(stick: .zero, dpad: SIMD2(1, 0))

        // Summing them would stop the character. The first input wins a tie instead.
        expectEqual(GamepadMapping.walking(keyboard: keyboard, gamepad: dpad), SIMD2(-100, 0))
    }

    @Test func strongestOfNothingIsZero() {
        expectEqual(GamepadMapping.strongest([SIMD2<Float>]()), .zero)
    }

    // MARK: Buttons

    @Test func buttonLayout() {
        #expect(GamepadMapping.action(for: .a) == .attack)
        #expect(GamepadMapping.action(for: .b) == .closeTopWindow)
        #expect(GamepadMapping.action(for: .x) == .shortcut(row: 0, slot: 0))
        #expect(GamepadMapping.action(for: .y) == .shortcut(row: 0, slot: 1))
        #expect(GamepadMapping.action(for: .leftShoulder) == .shortcut(row: 0, slot: 2))
        #expect(GamepadMapping.action(for: .rightShoulder) == .shortcut(row: 0, slot: 3))
        #expect(GamepadMapping.action(for: .leftTrigger) == .shortcut(row: 0, slot: 4))
        #expect(GamepadMapping.action(for: .rightTrigger) == .shortcut(row: 0, slot: 5))
        #expect(GamepadMapping.action(for: .menu) == .toggleOptions)
    }

    @Test func everyButtonHasADistinctNonMovementAction() {
        let actions = GamepadButton.allCases.map(GamepadMapping.action(for:))

        #expect(Set(actions).count == GamepadButton.allCases.count)
        for action in actions {
            #expect(action.movementDirection == nil)
        }
    }

    @Test func shortcutButtonsStayInsideTheNineSlotRow() {
        for button in GamepadButton.allCases {
            if case .shortcut(let row, let slot) = GamepadMapping.action(for: button) {
                #expect(row == 0)
                #expect((0..<9).contains(slot))
            }
        }
    }

    @Test func buttonsFireOnceWhenPressedNotWhileHeld() {
        #expect(GamepadMapping.newlyPressed(previous: [], current: []).isEmpty)
        #expect(GamepadMapping.newlyPressed(previous: [], current: [.a]) == [.a])
        // Still held.
        #expect(GamepadMapping.newlyPressed(previous: [.a], current: [.a]).isEmpty)
        // Released.
        #expect(GamepadMapping.newlyPressed(previous: [.a], current: []).isEmpty)
        // Pressed again after the release.
        #expect(GamepadMapping.newlyPressed(previous: [], current: [.a]) == [.a])
    }

    @Test func buttonsPressedTogetherFireInAStableOrder() {
        let presses = GamepadMapping.newlyPressed(previous: [.b], current: [.menu, .b, .x, .a])

        #expect(presses == [.a, .x, .menu])
    }
}
