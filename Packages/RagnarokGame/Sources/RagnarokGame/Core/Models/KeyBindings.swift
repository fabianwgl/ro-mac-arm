//
//  KeyBindings.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation

/// An action which can be triggered by the keyboard.
public enum GameAction: Hashable, Sendable, Identifiable {
    case shortcut(row: Int, slot: Int)
    case toggleInventory
    case toggleEquipment
    case toggleSkills
    case toggleStatus
    case toggleWorldMap
    case toggleOptions
    case focusChat
    case sitStand
    case nextShortcutRow
    case closeTopWindow

    public var id: String {
        switch self {
        case .shortcut(let row, let slot):
            "shortcut.\(row).\(slot)"
        case .toggleInventory:
            "toggleInventory"
        case .toggleEquipment:
            "toggleEquipment"
        case .toggleSkills:
            "toggleSkills"
        case .toggleStatus:
            "toggleStatus"
        case .toggleWorldMap:
            "toggleWorldMap"
        case .toggleOptions:
            "toggleOptions"
        case .focusChat:
            "focusChat"
        case .sitStand:
            "sitStand"
        case .nextShortcutRow:
            "nextShortcutRow"
        case .closeTopWindow:
            "closeTopWindow"
        }
    }

    public var title: String {
        switch self {
        case .shortcut(let row, let slot):
            "Shortcut \(row + 1)-\(slot + 1)"
        case .toggleInventory:
            "Inventory"
        case .toggleEquipment:
            "Equipment"
        case .toggleSkills:
            "Skills"
        case .toggleStatus:
            "Status"
        case .toggleWorldMap:
            "World Map"
        case .toggleOptions:
            "Options"
        case .focusChat:
            "Focus Chat"
        case .sitStand:
            "Sit / Stand"
        case .nextShortcutRow:
            "Next Shortcut Row"
        case .closeTopWindow:
            "Close Top Window"
        }
    }

    /// Every action shown by the key binding editor.
    public static let all: [GameAction] = {
        let shortcuts = (0..<3).flatMap { row in
            (0..<9).map { GameAction.shortcut(row: row, slot: $0) }
        }

        return shortcuts + [
            .toggleInventory,
            .toggleEquipment,
            .toggleSkills,
            .toggleStatus,
            .toggleWorldMap,
            .toggleOptions,
            .focusChat,
            .sitStand,
            .nextShortcutRow,
            .closeTopWindow,
        ]
    }()

    /// Rebuilds an action from the identifier stored in the key binding file.
    public init?(id: String) {
        if id.hasPrefix("shortcut.") {
            let components = id.split(separator: ".")
            guard components.count == 3,
                  let row = Int(components[1]),
                  let slot = Int(components[2]) else {
                return nil
            }
            self = .shortcut(row: row, slot: slot)
            return
        }

        switch id {
        case "toggleInventory":
            self = .toggleInventory
        case "toggleEquipment":
            self = .toggleEquipment
        case "toggleSkills":
            self = .toggleSkills
        case "toggleStatus":
            self = .toggleStatus
        case "toggleWorldMap":
            self = .toggleWorldMap
        case "toggleOptions":
            self = .toggleOptions
        case "focusChat":
            self = .focusChat
        case "sitStand":
            self = .sitStand
        case "nextShortcutRow":
            self = .nextShortcutRow
        case "closeTopWindow":
            self = .closeTopWindow
        default:
            return nil
        }
    }
}

/// A key and the modifiers which must be held to trigger a binding.
public struct KeyChord: Hashable, Sendable {
    public enum NamedKey: String, CaseIterable, Codable, Sendable {
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
        case escape
        case returnKey = "return"
        case insert
        case tab
        case space

        var displayString: String {
            switch self {
            case .f1: "F1"
            case .f2: "F2"
            case .f3: "F3"
            case .f4: "F4"
            case .f5: "F5"
            case .f6: "F6"
            case .f7: "F7"
            case .f8: "F8"
            case .f9: "F9"
            case .f10: "F10"
            case .f11: "F11"
            case .f12: "F12"
            case .escape: "Esc"
            case .returnKey: "Return"
            case .insert: "Insert"
            case .tab: "Tab"
            case .space: "Space"
            }
        }
    }

    public enum Key: Hashable, Sendable {
        case character(Character)
        case named(NamedKey)
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let option = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Converts a keyboard event into a binding.
    ///
    /// `charactersIgnoringModifiers` is used for letters so that Option combinations are
    /// matched by the letter printed on the key, not by the composed character macOS
    /// produces (Option-E yields `´` in `characters`).
    public init?(
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: Modifiers
    ) {
        if let namedKey = Self.namedKeysByKeyCode[keyCode] {
            self.init(key: .named(namedKey), modifiers: modifiers)
            return
        }

        let text = charactersIgnoringModifiers ?? characters
        guard let first = text?.first,
              let character = first.lowercased().first,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol else {
            return nil
        }

        self.init(key: .character(character), modifiers: modifiers)
    }

    public var displayString: String {
        var displayString = ""

        if modifiers.contains(.control) {
            displayString += "⌃"
        }
        if modifiers.contains(.option) {
            displayString += "⌥"
        }
        if modifiers.contains(.shift) {
            displayString += "⇧"
        }
        if modifiers.contains(.command) {
            displayString += "⌘"
        }

        switch key {
        case .character(let character):
            displayString += String(character).uppercased()
        case .named(let namedKey):
            displayString += namedKey.displayString
        }

        return displayString
    }

    private static let namedKeysByKeyCode: [UInt16: NamedKey] = [
        122: .f1,
        120: .f2,
        99: .f3,
        118: .f4,
        96: .f5,
        97: .f6,
        98: .f7,
        100: .f8,
        101: .f9,
        109: .f10,
        103: .f11,
        111: .f12,
        53: .escape,
        36: .returnKey,
        114: .insert,
        48: .tab,
        49: .space,
    ]
}

extension KeyChord: Codable {
    private enum CodingKeys: String, CodingKey {
        case character
        case namedKey
        case modifiers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modifiers = try container.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []

        if let namedKey = try container.decodeIfPresent(NamedKey.self, forKey: .namedKey) {
            self.init(key: .named(namedKey), modifiers: modifiers)
            return
        }

        let text = try container.decode(String.self, forKey: .character)
        guard let character = text.first else {
            throw DecodingError.dataCorruptedError(
                forKey: .character,
                in: container,
                debugDescription: "A key binding has no character."
            )
        }

        self.init(key: .character(character), modifiers: modifiers)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch key {
        case .character(let character):
            try container.encode(String(character), forKey: .character)
        case .named(let namedKey):
            try container.encode(namedKey, forKey: .namedKey)
        }

        try container.encode(modifiers, forKey: .modifiers)
    }
}

extension KeyChord.Modifiers: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// User-editable key bindings, persisted as JSON in user defaults.
@MainActor
@Observable
public final class KeyBindings {
    public static let defaultsKey = "game.keybindings"

    private(set) var chords: [GameAction: KeyChord]

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.chords = Self.loadChords(from: defaults)
    }

    public func chord(for action: GameAction) -> KeyChord? {
        chords[action]
    }

    public func action(for chord: KeyChord) -> GameAction? {
        chords.first { $0.value == chord }?.key
    }

    /// Assigns a chord to an action. A chord which already belongs to another action
    /// is removed from that action, so a chord never triggers two actions.
    public func setChord(_ chord: KeyChord?, for action: GameAction) {
        if let chord, let otherAction = self.action(for: chord), otherAction != action {
            chords[otherAction] = nil
        }
        chords[action] = chord
        save()
    }

    public func resetToDefaults() {
        chords = Self.defaultChords
        save()
    }

    private func save() {
        let storedChords = Dictionary(uniqueKeysWithValues: chords.map { ($0.key.id, $0.value) })
        guard let data = try? JSONEncoder().encode(storedChords) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func loadChords(from defaults: UserDefaults) -> [GameAction: KeyChord] {
        guard let data = defaults.data(forKey: defaultsKey),
              let storedChords = try? JSONDecoder().decode([String: KeyChord].self, from: data) else {
            return defaultChords
        }

        var chords: [GameAction: KeyChord] = [:]
        var usedChords: Set<KeyChord> = []
        for (actionID, chord) in storedChords {
            guard let action = GameAction(id: actionID), !usedChords.contains(chord) else {
                continue
            }
            chords[action] = chord
            usedChords.insert(chord)
        }
        return chords
    }

    private static let defaultChords: [GameAction: KeyChord] = {
        var chords: [GameAction: KeyChord] = [:]

        let functionKeys: [KeyChord.NamedKey] = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9,
        ]
        for (slot, namedKey) in functionKeys.enumerated() {
            chords[.shortcut(row: 0, slot: slot)] = KeyChord(key: .named(namedKey))
        }

        for (slot, character) in "123456789".enumerated() {
            chords[.shortcut(row: 1, slot: slot)] = KeyChord(key: .character(character))
        }

        for (slot, character) in "qwertyuio".enumerated() {
            chords[.shortcut(row: 2, slot: slot)] = KeyChord(key: .character(character))
        }

        chords[.toggleInventory] = KeyChord(key: .character("e"), modifiers: .option)
        chords[.toggleEquipment] = KeyChord(key: .character("q"), modifiers: .option)
        chords[.toggleSkills] = KeyChord(key: .character("s"), modifiers: .option)
        chords[.toggleStatus] = KeyChord(key: .character("a"), modifiers: .option)

        // The parity document lists Alt+M as the shortcut settings shortcut. Basic info
        // (Alt+V) is always on screen, so it has no separate action here. The world map
        // has no kRO shortcut, so it starts unbound.
        chords[.toggleOptions] = KeyChord(key: .character("m"), modifiers: .option)

        chords[.focusChat] = KeyChord(key: .named(.returnKey))
        chords[.closeTopWindow] = KeyChord(key: .named(.escape))
        chords[.sitStand] = KeyChord(key: .named(.insert))
        chords[.nextShortcutRow] = KeyChord(key: .named(.f12))

        return chords
    }()
}
