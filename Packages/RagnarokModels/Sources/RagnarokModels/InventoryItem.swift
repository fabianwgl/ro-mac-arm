//
//  InventoryItem.swift
//  RagnarokModels
//
//  Created by Leon Li on 2025/4/15.
//

import RagnarokConstants
import RagnarokPackets

public struct InventoryItem: Sendable {
    public var index: Int
    public var itemID: Int
    public var type: ItemType
    public var amount: Int
    public var location: EquipPositions
    public var equippedLocation: EquipPositions
    public var slots: [Int]

    /// False for equipment that dropped and has not been appraised. The server gives such an item its unidentified
    /// name (`Dagger` for a Knife) until a Magnifier is used on it.
    public var isIdentified: Bool

    public var isUsable: Bool {
        switch type {
        case .healing, .usable, .delayconsume, .cash: true
        default: false
        }
    }

    public var isEquippable: Bool {
        switch type {
        case .weapon, .armor, .shadowgear, .petegg, .petarmor, .ammo: true
        default: false
        }
    }

    public var isEquipped: Bool {
        !equippedLocation.isEmpty && type != .card
    }

    public var isEtc: Bool {
        switch type {
        case .etc, .card: true
        default: false
        }
    }

    public init() {
        index = 0
        itemID = 0
        type = .etc
        amount = 0
        location = EquipPositions(rawValue: 0)
        equippedLocation = EquipPositions(rawValue: 0)
        slots = [0, 0, 0, 0]
        isIdentified = true
    }

    public init(from item: NORMALITEM_INFO) {
        index = Int(item.index)
        itemID = Int(item.ITID)
        type = ItemType(rawValue: Int(item.type)) ?? .etc
        amount = Int(item.count)
        location = EquipPositions(rawValue: 0)
        equippedLocation = EquipPositions(rawValue: Int(item.WearState))
        slots = item.slot.card.map(Int.init)
        isIdentified = Self.isIdentified(flag: item.Flag)
    }

    public init(from item: EQUIPITEM_INFO) {
        index = Int(item.index)
        itemID = Int(item.ITID)
        type = ItemType(rawValue: Int(item.type)) ?? .etc
        amount = 1
        location = EquipPositions(rawValue: Int(item.location))
        equippedLocation = EquipPositions(rawValue: Int(item.WearState))
        slots = item.slot.card.map(Int.init)
        isIdentified = Self.isIdentified(flag: item.Flag)
    }

    /// The `Flag` byte of an item list entry is a bit field; its first bit is `IsIdentified`.
    static func isIdentified(flag: UInt8) -> Bool {
        flag & 0x01 != 0
    }
}

extension InventoryItem: Comparable {
    public static func < (lhs: InventoryItem, rhs: InventoryItem) -> Bool {
        lhs.index < rhs.index
    }
}
