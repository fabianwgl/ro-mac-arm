//
//  KeyBindingsTests.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokGame

@MainActor
struct KeyBindingsTests {
    @Test func defaults() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let keyBindings = KeyBindings(defaults: testDefaults.defaults)

        let functionKeys: [KeyChord.NamedKey] = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9,
        ]
        for (slot, namedKey) in functionKeys.enumerated() {
            #expect(keyBindings.chord(for: .shortcut(row: 0, slot: slot)) == KeyChord(key: .named(namedKey)))
        }

        for (slot, character) in "123456789".enumerated() {
            #expect(keyBindings.chord(for: .shortcut(row: 1, slot: slot)) == KeyChord(key: .character(character)))
        }

        for (slot, character) in "qwertyuio".enumerated() {
            #expect(keyBindings.chord(for: .shortcut(row: 2, slot: slot)) == KeyChord(key: .character(character)))
        }

        #expect(keyBindings.chord(for: .toggleInventory) == KeyChord(key: .character("e"), modifiers: .option))
        #expect(keyBindings.chord(for: .toggleEquipment) == KeyChord(key: .character("q"), modifiers: .option))
        #expect(keyBindings.chord(for: .toggleSkills) == KeyChord(key: .character("s"), modifiers: .option))
        #expect(keyBindings.chord(for: .toggleStatus) == KeyChord(key: .character("a"), modifiers: .option))
        #expect(keyBindings.chord(for: .togglePet) == KeyChord(key: .character("j"), modifiers: .option))
        #expect(keyBindings.chord(for: .toggleHomunculus) == KeyChord(key: .character("r"), modifiers: .option))
        #expect(keyBindings.chord(for: .toggleOptions) == KeyChord(key: .character("m"), modifiers: .option))
        #expect(keyBindings.chord(for: .focusChat) == KeyChord(key: .named(.returnKey)))
        #expect(keyBindings.chord(for: .closeTopWindow) == KeyChord(key: .named(.escape)))
        #expect(keyBindings.chord(for: .sitStand) == KeyChord(key: .named(.insert)))
        #expect(keyBindings.chord(for: .nextShortcutRow) == KeyChord(key: .named(.f12)))
        #expect(keyBindings.chord(for: .toggleWorldMap) == nil)
    }

    @Test func persistenceRoundTrip() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let keyBindings = KeyBindings(defaults: testDefaults.defaults)
        let chord = KeyChord(key: .named(.f10))
        keyBindings.setChord(chord, for: .sitStand)

        let reloaded = KeyBindings(defaults: testDefaults.defaults)
        #expect(reloaded.chord(for: .sitStand) == chord)
        #expect(reloaded.action(for: chord) == .sitStand)
    }

    @Test func rebindingAUsedChordUnbindsItsPreviousAction() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let keyBindings = KeyBindings(defaults: testDefaults.defaults)
        let chord = KeyChord(key: .character("e"), modifiers: .option)

        keyBindings.setChord(chord, for: .shortcut(row: 0, slot: 0))

        #expect(keyBindings.chord(for: .toggleInventory) == nil)
        #expect(keyBindings.chord(for: .shortcut(row: 0, slot: 0)) == chord)
        #expect(keyBindings.action(for: chord) == .shortcut(row: 0, slot: 0))
    }

    @Test func clearUnbindsAnAction() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let keyBindings = KeyBindings(defaults: testDefaults.defaults)
        keyBindings.setChord(nil, for: .toggleInventory)

        #expect(keyBindings.chord(for: .toggleInventory) == nil)
        #expect(keyBindings.action(for: KeyChord(key: .character("e"), modifiers: .option)) == nil)
    }

    @Test func resetRestoresDefaults() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let keyBindings = KeyBindings(defaults: testDefaults.defaults)
        keyBindings.setChord(nil, for: .toggleInventory)
        keyBindings.resetToDefaults()

        #expect(keyBindings.chord(for: .toggleInventory) == KeyChord(key: .character("e"), modifiers: .option))
    }

    @Test func corruptStoredDataUsesDefaults() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        testDefaults.defaults.set(Data("not json".utf8), forKey: KeyBindings.defaultsKey)

        let keyBindings = KeyBindings(defaults: testDefaults.defaults)
        #expect(keyBindings.chord(for: .shortcut(row: 0, slot: 0)) == KeyChord(key: .named(.f1)))
        #expect(keyBindings.chord(for: .toggleInventory) == KeyChord(key: .character("e"), modifiers: .option))
    }

    @Test func displayStrings() {
        #expect(KeyChord(key: .named(.f1)).displayString == "F1")
        #expect(KeyChord(key: .character("e"), modifiers: .option).displayString == "⌥E")
    }

    @Test func keyEventTranslation() {
        let optionE = KeyChord(
            keyCode: 14,
            characters: "´",
            charactersIgnoringModifiers: "e",
            modifiers: .option
        )
        #expect(optionE == KeyChord(key: .character("e"), modifiers: .option))

        let shiftE = KeyChord(
            keyCode: 14,
            characters: "E",
            charactersIgnoringModifiers: "E",
            modifiers: .shift
        )
        #expect(shiftE == KeyChord(key: .character("e"), modifiers: .shift))

        let f1 = KeyChord(
            keyCode: 122,
            characters: nil,
            charactersIgnoringModifiers: nil,
            modifiers: []
        )
        #expect(f1 == KeyChord(key: .named(.f1)))

        let returnKey = KeyChord(
            keyCode: 36,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: []
        )
        #expect(returnKey == KeyChord(key: .named(.returnKey)))

        let escape = KeyChord(
            keyCode: 53,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: []
        )
        #expect(escape == KeyChord(key: .named(.escape)))

        let arrowKey = KeyChord(
            keyCode: 123,
            characters: "\u{F702}",
            charactersIgnoringModifiers: "\u{F702}",
            modifiers: []
        )
        #expect(arrowKey == nil)
    }

    private struct TestDefaults {
        let suiteName = "KeyBindingsTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
