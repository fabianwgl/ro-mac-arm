//
//  PetState.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// The hunger scale of pets and homunculi. rAthena keeps hunger from 0 to 100, see
/// `pet_hungry_val` and the `PET_HUNGRY_*` constants.
enum CompanionHunger: Int, CaseIterable, Sendable {
    case veryHungry
    case hungry
    case neutral
    case satisfied
    case stuffed

    init(value: Int) {
        switch value {
        case ...10:
            self = .veryHungry
        case ...25:
            self = .hungry
        case ...75:
            self = .neutral
        case ...90:
            self = .satisfied
        default:
            self = .stuffed
        }
    }

    var title: String {
        switch self {
        case .veryHungry: "Very hungry"
        case .hungry: "Hungry"
        case .neutral: "Neutral"
        case .satisfied: "Satisfied"
        case .stuffed: "Stuffed"
        }
    }
}

/// A pet: the one which is out of its egg, if the player has hatched one.
///
/// `ZC_PROPERTY_PET` carries the name, level, hunger, intimacy and accessory. `ZC_CHANGESTATE_PET`
/// keeps hunger and intimacy current and names the pet's object ID. Only the owner receives
/// hunger and intimacy updates, while accessory changes are broadcast to everyone nearby.
struct PetState: Equatable, Sendable {
    enum Intimacy: Int, CaseIterable, Sendable {
        case awkward
        case shy
        case neutral
        case cordial
        case loyal

        /// The `PET_INTIMATE_*` thresholds: 100 shy, 250 neutral, 750 cordial, 910 loyal.
        init(value: Int) {
            switch value {
            case ..<100:
                self = .awkward
            case ..<250:
                self = .shy
            case ..<750:
                self = .neutral
            case ..<910:
                self = .cordial
            default:
                self = .loyal
            }
        }

        var title: String {
            switch self {
            case .awkward: "Awkward"
            case .shy: "Shy"
            case .neutral: "Neutral"
            case .cordial: "Cordial"
            case .loyal: "Loyal"
            }
        }
    }

    /// The `type` field of `ZC_CHANGESTATE_PET`, see `e_changestate_pet`.
    enum StateChange: Int, Sendable {
        case initialize = 0
        case intimacy = 1
        case hunger = 2
        case accessory = 3
        case performance = 4
        case hairstyle = 5
        /// Closes the egg selection and updates the egg in the inventory.
        case updateEgg = 6
    }

    /// What the caller has to do after a state change.
    enum StateChangeEffect: Equatable, Sendable {
        case none
        /// The accessory changed and `ZC_PROPERTY_PET` is not resent, so ask for it again.
        case refreshInformation
        case closeEggSelection
    }

    static let maxHunger = 100
    static let maxIntimacy = 1000

    /// True from `ZC_PROPERTY_PET` until the pet leaves the map.
    private(set) var isActive = false
    private(set) var name = ""
    /// A pet can be renamed once, unless the server allows more.
    private(set) var isRenamed = false
    private(set) var level = 0
    private(set) var hunger = 0
    private(set) var intimacy = 0
    /// Item ID of the equipped accessory, 0 for none.
    private(set) var accessoryItemID = 0
    /// Monster class of the pet.
    private(set) var classID = 0
    private(set) var objectID: UInt32?

    /// Whether the server feeds the pet by itself. It only answers `CZ_CONFIG` when the pet allows it.
    private(set) var isAutoFeedEnabled = false

    var hasAccessory: Bool {
        accessoryItemID > 0
    }

    var canRename: Bool {
        isActive && !isRenamed
    }

    var hungerLevel: CompanionHunger {
        CompanionHunger(value: hunger)
    }

    var intimacyLevel: Intimacy {
        Intimacy(value: intimacy)
    }

    var hungerFraction: Double {
        Double(min(max(hunger, 0), Self.maxHunger)) / Double(Self.maxHunger)
    }

    var intimacyFraction: Double {
        Double(min(max(intimacy, 0), Self.maxIntimacy)) / Double(Self.maxIntimacy)
    }

    init() {
    }

    /// Applies `ZC_PROPERTY_PET`.
    mutating func applyProperties(
        name: String,
        isRenamed: Bool,
        level: Int,
        hunger: Int,
        intimacy: Int,
        accessoryItemID: Int,
        classID: Int
    ) {
        self.isActive = true
        self.name = name
        self.isRenamed = isRenamed
        self.level = level
        self.hunger = min(max(hunger, 0), Self.maxHunger)
        self.intimacy = min(max(intimacy, 0), Self.maxIntimacy)
        self.accessoryItemID = max(accessoryItemID, 0)
        self.classID = classID
    }

    /// Applies `ZC_CHANGESTATE_PET`.
    @discardableResult
    mutating func applyStateChange(type: Int, objectID: UInt32, value: Int) -> StateChangeEffect {
        guard let change = StateChange(rawValue: type) else {
            return .none
        }

        switch change {
        case .initialize:
            // A different pet object means a new pet, such as one hatched from another egg.
            if let current = self.objectID, current != objectID {
                reset()
            }
            self.objectID = objectID
        case .intimacy:
            guard isActive else {
                return .none
            }
            intimacy = min(max(value, 0), Self.maxIntimacy)
        case .hunger:
            guard isActive else {
                return .none
            }
            hunger = min(max(value, 0), Self.maxHunger)
        case .accessory:
            // Sent to everyone nearby, so only the player's own pet counts.
            guard let current = self.objectID, current == objectID else {
                return .none
            }
            return .refreshInformation
        case .updateEgg:
            return .closeEggSelection
        case .performance, .hairstyle:
            break
        }
        return .none
    }

    /// Applies `ZC_CONFIG` for pet auto feed.
    mutating func setAutoFeedEnabled(_ isEnabled: Bool) {
        isAutoFeedEnabled = isEnabled
    }

    /// Clears the pet when its object leaves the map, such as when it returns to its egg.
    /// Returns true when the vanished object was the player's pet.
    @discardableResult
    mutating func petVanished(objectID: UInt32) -> Bool {
        guard let current = self.objectID, current == objectID else {
            return false
        }
        reset()
        return true
    }

    mutating func reset() {
        self = PetState()
    }
}

/// The rules `pet_change_name` and `hom_change_name` apply to a new name.
enum CompanionName {
    /// The name field is 24 bytes and the server reads it as a NUL terminated string.
    static let maxByteCount = 23

    /// The trimmed name, or nil when the server would refuse it: empty, too long, or with control characters.
    static func validated(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= maxByteCount else {
            return nil
        }
        guard name.utf8.allSatisfy({ $0 >= 0x20 && $0 != 0x7f }) else {
            return nil
        }
        return name
    }
}
