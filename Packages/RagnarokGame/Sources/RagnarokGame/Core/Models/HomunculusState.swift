//
//  HomunculusState.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// The player's homunculus.
///
/// `ZC_PROPERTY_HOMUN` carries everything at once and is the only source of whether the
/// homunculus is active, vaporized, dead or gone (see `clif_hominfo`). `ZC_HO_PAR_CHANGE` updates
/// HP, SP and experience, `ZC_CHANGESTATE_MER` hunger and intimacy, and `ZC_HOSKILLINFO_LIST` the skills.
struct HomunculusState: Equatable, Sendable {
    /// The grades of `hom_intimacy_intimacy2grade`. The packet carries intimacy divided by 100,
    /// so the thresholds are 4, 11, 101, 251, 751 and 911 of 1000.
    enum Intimacy: Int, CaseIterable, Sendable {
        case hateWithPassion
        case hate
        case awkward
        case shy
        case neutral
        case cordial
        case loyal

        init(value: Int) {
            switch value {
            case ..<4:
                self = .hateWithPassion
            case ..<11:
                self = .hate
            case ..<101:
                self = .awkward
            case ..<251:
                self = .shy
            case ..<751:
                self = .neutral
            case ..<911:
                self = .cordial
            default:
                self = .loyal
            }
        }

        var title: String {
            switch self {
            case .hateWithPassion: "Hate with passion"
            case .hate: "Hate"
            case .awkward: "Awkward"
            case .shy: "Shy"
            case .neutral: "Neutral"
            case .cordial: "Cordial"
            case .loyal: "Loyal"
            }
        }
    }

    enum Condition: Equatable, Sendable {
        case active
        /// Resting in the vaporized state, brought back by the call skill.
        case vaporized
        /// At 0 HP and out of the map, brought back by the resurrect skill.
        case dead

        var title: String {
            switch self {
            case .active: "Active"
            case .vaporized: "Vaporized"
            case .dead: "Dead"
            }
        }
    }

    /// Everything `ZC_PROPERTY_HOMUN` sends.
    struct Properties: Equatable, Sendable {
        var name: String
        /// Bit 0 of the packet flags.
        var isRenamed: Bool
        /// Bit 1 of the packet flags.
        var isVaporized: Bool
        /// Bit 2 of the packet flags, set while the homunculus has HP left.
        var isAlive: Bool
        var level: Int
        var hunger: Int
        var intimacy: Int
        var atk: Int
        var matk: Int
        var hit: Int
        var critical: Int
        var def: Int
        var mdef: Int
        var flee: Int
        /// Attack motion, lower is faster.
        var attackMotion: Int
        var hp: Int
        var maxHP: Int
        var sp: Int
        var maxSP: Int
        var exp: Int64
        /// 0 at the maximum level.
        var expNext: Int64
        var skillPoints: Int
        var attackRange: Int
    }

    struct Skill: Identifiable, Equatable, Sendable {
        var id: Int
        /// The server's identifier such as `HLIF_HEAL`.
        var identifier: String
        var level: Int
        var spCost: Int
        var range: Int
        var isUpgradable: Bool
    }

    static let maxHunger = 100
    static let maxIntimacy = 1000

    /// True once `ZC_PROPERTY_HOMUN` arrived, until the server deletes the homunculus.
    private(set) var isPresent = false
    private(set) var properties = Properties(
        name: "", isRenamed: false, isVaporized: false, isAlive: true, level: 0, hunger: 0, intimacy: 0,
        atk: 0, matk: 0, hit: 0, critical: 0, def: 0, mdef: 0, flee: 0, attackMotion: 0,
        hp: 0, maxHP: 0, sp: 0, maxSP: 0, exp: 0, expNext: 0, skillPoints: 0, attackRange: 0
    )
    private(set) var objectID: UInt32?
    private(set) var isAutoFeedEnabled = false
    private(set) var skills: [Skill] = []

    var name: String {
        properties.name
    }

    var condition: Condition {
        if properties.isVaporized {
            .vaporized
        } else if !properties.isAlive {
            .dead
        } else {
            .active
        }
    }

    /// The server refuses a rename unless the homunculus is out.
    var canRename: Bool {
        isActive && !properties.isRenamed
    }

    /// Feeding, renaming, deleting and the move command only work while the homunculus is out.
    var isActive: Bool {
        isPresent && condition == .active
    }

    var hungerLevel: CompanionHunger {
        CompanionHunger(value: properties.hunger)
    }

    var intimacyLevel: Intimacy {
        Intimacy(value: properties.intimacy)
    }

    var hungerFraction: Double {
        Double(min(max(properties.hunger, 0), Self.maxHunger)) / Double(Self.maxHunger)
    }

    var intimacyFraction: Double {
        Double(min(max(properties.intimacy, 0), Self.maxIntimacy)) / Double(Self.maxIntimacy)
    }

    var hpFraction: Double {
        fraction(properties.hp, of: properties.maxHP)
    }

    var spFraction: Double {
        fraction(properties.sp, of: properties.maxSP)
    }

    /// Progress to the next level, 0 at the maximum level.
    var expFraction: Double {
        guard properties.expNext > 0 else {
            return 0
        }
        return min(max(Double(properties.exp) / Double(properties.expNext), 0), 1)
    }

    var isAtMaxLevel: Bool {
        isPresent && properties.expNext == 0
    }

    init() {
    }

    /// Applies `ZC_PROPERTY_HOMUN`.
    ///
    /// A homunculus which the server deleted comes with 0 intimacy, 0 HP and neither the vaporized
    /// flag nor the alive flag (`hom_delete`), and is cleared here.
    mutating func apply(_ properties: Properties) {
        var properties = properties
        properties.hunger = min(max(properties.hunger, 0), Self.maxHunger)
        properties.intimacy = min(max(properties.intimacy, 0), Self.maxIntimacy)

        if properties.intimacy == 0 && !properties.isAlive && !properties.isVaporized {
            reset()
            return
        }

        self.isPresent = true
        self.properties = properties
    }

    /// Applies `ZC_HO_PAR_CHANGE`. Only HP, SP and base experience are ever sent.
    mutating func applyParameterChange(type: Int, value: Int64) {
        guard isPresent else {
            return
        }

        switch type {
        case 1: // SP_BASEEXP
            properties.exp = value
        case 5: // SP_HP
            properties.hp = Int(clamping: value)
            properties.isAlive = value > 0
        case 7: // SP_SP
            properties.sp = Int(clamping: value)
        default:
            break
        }
    }

    /// Applies `ZC_CHANGESTATE_MER`. `state` 0 is the pre-init packet which names the object,
    /// 1 carries intimacy and 2 hunger.
    mutating func applyStateChange(state: Int, objectID: UInt32, value: Int) {
        switch state {
        case 0:
            self.objectID = objectID
        case 1:
            guard isPresent else {
                return
            }
            properties.intimacy = min(max(value, 0), Self.maxIntimacy)
        case 2:
            guard isPresent else {
                return
            }
            properties.hunger = min(max(value, 0), Self.maxHunger)
        default:
            break
        }
    }

    /// Applies `ZC_HOSKILLINFO_LIST`, which holds every skill the homunculus has.
    mutating func apply(skills: [Skill]) {
        self.skills = skills
    }

    /// Applies `ZC_HOSKILLINFO_UPDATE`.
    mutating func updateSkill(id: Int, level: Int, spCost: Int, range: Int, isUpgradable: Bool) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else {
            return
        }

        skills[index].level = level
        skills[index].spCost = spCost
        skills[index].range = range
        skills[index].isUpgradable = isUpgradable
    }

    /// Applies `ZC_CONFIG` for homunculus auto feed.
    mutating func setAutoFeedEnabled(_ isEnabled: Bool) {
        isAutoFeedEnabled = isEnabled
    }

    mutating func reset() {
        self = HomunculusState()
    }

    private func fraction(_ value: Int, of maximum: Int) -> Double {
        guard maximum > 0 else {
            return 0
        }
        return min(max(Double(value) / Double(maximum), 0), 1)
    }
}
