//
//  PlaySession+Companions.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokConstants
import RagnarokModels
import RagnarokNetwork
import RagnarokPackets

/// The player's pet and homunculus, and the pet egg selection which a pet incubator opens.
@Observable
final class CompanionState {
    var pet = PetState()
    var homunculus = HomunculusState()

    /// Client inventory indices of the eggs the server offers, while the selection is open.
    var petEggIndices: [Int]?
}

extension PlaySession {
    /// Handles pet and homunculus packets. Returns false when the packet is not one of them.
    func handleCompanionPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_PETEGG_LIST:
            companions.petEggIndices = packet.indices.map(Int.init)
        case let packet as PACKET_ZC_PROPERTY_PET:
            companions.pet.applyProperties(
                name: packet.szName,
                isRenamed: packet.bModified != 0,
                level: Int(packet.nLevel),
                hunger: Int(packet.nFullness),
                intimacy: Int(packet.nRelationship),
                accessoryItemID: Int(UInt16(bitPattern: packet.ITID)),
                classID: Int(UInt16(bitPattern: packet.job))
            )
        case let packet as PACKET_ZC_CHANGESTATE_PET:
            handlePetStateChange(packet)
        case let packet as PACKET_ZC_FEED_PET:
            handleFeedResult(packet.result != 0, itemID: packet.itemId, subject: "pet")
        case let packet as PACKET_ZC_PROPERTY_HOMUN:
            companions.homunculus.apply(homunculusProperties(from: packet))
        case let packet as PACKET_ZC_HO_PAR_CHANGE:
            companions.homunculus.applyParameterChange(
                type: Int(packet.type),
                value: Int64(clamping: packet.value)
            )
        case let packet as PACKET_ZC_CHANGESTATE_MER:
            companions.homunculus.applyStateChange(
                state: Int(packet.state),
                objectID: packet.gid,
                value: Int(packet.data)
            )
        case let packet as PACKET_ZC_FEED_MER:
            handleFeedResult(packet.result != 0, itemID: packet.itemId, subject: "homunculus")
        case let packet as PACKET_ZC_HOSKILLINFO_LIST:
            companions.homunculus.apply(skills: packet.skills.map(homunculusSkill(from:)))
        case let packet as PACKET_ZC_HOSKILLINFO_UPDATE:
            companions.homunculus.updateSkill(
                id: Int(packet.skill_id),
                level: Int(packet.Level),
                spCost: Int(packet.SP),
                range: Int(packet.AttackRange),
                isUpgradable: packet.upgradable != 0
            )
        case let packet as PACKET_ZC_CONFIG:
            return handleCompanionConfig(packet)
        default:
            return false
        }
        return true
    }

    /// A pet leaves the map when it returns to its egg, runs away or is released.
    func handleCompanionVanish(objectID: GameObjectID) {
        companions.pet.petVanished(objectID: objectID)
    }

    // MARK: - Pet Requests

    func requestPetInformation() {
        sendPacket(PacketFactory.CZ_COMMAND_PET(command: .information))
    }

    func feedPet() {
        guard requirePet() else {
            return
        }
        sendPacket(PacketFactory.CZ_COMMAND_PET(command: .feed))
    }

    func performPet() {
        guard requirePet() else {
            return
        }
        sendPacket(PacketFactory.CZ_COMMAND_PET(command: .performance))
    }

    func returnPetToEgg() {
        guard requirePet() else {
            return
        }
        sendPacket(PacketFactory.CZ_COMMAND_PET(command: .returnToEgg))
    }

    func unequipPetAccessory() {
        guard requirePet() else {
            return
        }
        guard companions.pet.hasAccessory else {
            addCompanionMessage("Your pet has no accessory.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_COMMAND_PET(command: .unequipAccessory))
    }

    func renamePet(to name: String) {
        guard requirePet() else {
            return
        }
        guard companions.pet.canRename else {
            addCompanionMessage("Your pet has already been renamed.", type: .error)
            return
        }
        guard let name = CompanionName.validated(name) else {
            addCompanionMessage("Enter a name of 1 to \(CompanionName.maxByteCount) characters.", type: .error)
            return
        }
        // The server answers with ZC_PROPERTY_PET, or with a message and the old name when it
        // refuses the name.
        sendPacket(PacketFactory.CZ_RENAME_PET(name: name))
    }

    /// The server answers with `ZC_CONFIG` when it accepts, so the toggle follows its answer.
    func setPetAutoFeed(_ isEnabled: Bool) {
        guard requirePet() else {
            return
        }
        sendPacket(PacketFactory.CZ_CONFIG(type: .petAutofeed, enabled: isEnabled))
    }

    func selectPetEgg(inventoryIndex: Int) {
        guard let indices = companions.petEggIndices, indices.contains(inventoryIndex) else {
            return
        }

        companions.petEggIndices = nil
        sendPacket(PacketFactory.CZ_SELECT_PETEGG(index: UInt16(truncatingIfNeeded: inventoryIndex)))
    }

    func cancelPetEggSelection() {
        guard companions.petEggIndices != nil else {
            return
        }

        companions.petEggIndices = nil
        sendPacket(PacketFactory.CZ_SELECT_PETEGG(index: PACKET_CZ_SELECT_PETEGG.cancelIndex))
    }

    // MARK: - Homunculus Requests

    func feedHomunculus() {
        guard companions.homunculus.isActive else {
            addCompanionMessage("Your homunculus is not out.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_COMMAND_MER(command: .feed))
    }

    /// Deletes the homunculus for good. The server removes it and sends it with 0 intimacy.
    /// It ignores the command unless the homunculus is out and alive (`hom_is_active`).
    func deleteHomunculus() {
        guard companions.homunculus.isActive else {
            addCompanionMessage("Your homunculus is not out.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_COMMAND_MER(command: .delete))
    }

    func renameHomunculus(to name: String) {
        guard companions.homunculus.isActive else {
            addCompanionMessage("Your homunculus is not out.", type: .error)
            return
        }
        guard companions.homunculus.canRename else {
            addCompanionMessage("Your homunculus has already been renamed.", type: .error)
            return
        }
        guard let name = CompanionName.validated(name) else {
            addCompanionMessage("Enter a name of 1 to \(CompanionName.maxByteCount) characters.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_RENAME_MER(name: name))
    }

    func moveHomunculusToOwner() {
        guard companions.homunculus.isActive, let objectID = companions.homunculus.objectID else {
            addCompanionMessage("Your homunculus is not out.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_REQUEST_MOVETOOWNER(objectID: objectID))
    }

    /// The server ignores it while the homunculus is vaporized.
    func setHomunculusAutoFeed(_ isEnabled: Bool) {
        guard companions.homunculus.isPresent, companions.homunculus.condition != .vaporized else {
            addCompanionMessage("Your homunculus is not out.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_CONFIG(type: .homunculusAutofeed, enabled: isEnabled))
    }

    /// Whether the player has learned a skill which looks after the homunculus.
    func canUseHomunculusSkill(_ skillID: SkillID) -> Bool {
        (skillList.skills[skillID.rawValue]?.level ?? 0) > 0
    }

    /// The server has no packet for calling, vaporizing or resurrecting a homunculus. They are the
    /// player's skills `AM_CALLHOMUN`, `AM_REST` and `AM_RESURRECTHOMUN`, which target the player.
    func useHomunculusSkill(_ skillID: SkillID) {
        guard let skill = skillList.skills[skillID.rawValue], skill.level > 0 else {
            addCompanionMessage("You have not learned that skill.", type: .error)
            return
        }
        mapScene?.useSkill(skill, level: skill.level)
    }

    // MARK: - Packet Handling

    private func handlePetStateChange(_ packet: PACKET_ZC_CHANGESTATE_PET) {
        let effect = companions.pet.applyStateChange(
            type: Int(packet.type),
            objectID: UInt32(bitPattern: packet.GID),
            value: Int(packet.data)
        )

        switch effect {
        case .none:
            break
        case .refreshInformation:
            requestPetInformation()
        case .closeEggSelection:
            companions.petEggIndices = nil
        }
    }

    private func handleCompanionConfig(_ packet: PACKET_ZC_CONFIG) -> Bool {
        // Other options such as the equipment window are not the companions' business.
        switch PACKET_CZ_CONFIG.ConfigType(rawValue: UInt32(bitPattern: packet.type)) {
        case .petAutofeed:
            companions.pet.setAutoFeedEnabled(packet.value != 0)
        case .homunculusAutofeed:
            companions.homunculus.setAutoFeedEnabled(packet.value != 0)
        default:
            return false
        }
        return true
    }

    private func handleFeedResult(_ isSuccess: Bool, itemID: UInt32, subject: String) {
        if isSuccess {
            addCompanionMessage("Your \(subject) has been fed.")
        } else {
            let itemName = messageCenter.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(itemID)) ?? "item \(itemID)"
            addCompanionMessage("You have no \(itemName) to feed your \(subject).", type: .error)
        }
    }

    // MARK: - Packet Conversion

    private func homunculusProperties(from packet: PACKET_ZC_PROPERTY_HOMUN) -> HomunculusState.Properties {
        HomunculusState.Properties(
            name: packet.name,
            isRenamed: packet.flags & 0x1 != 0,
            isVaporized: packet.flags & 0x2 != 0,
            isAlive: packet.flags & 0x4 != 0,
            level: Int(packet.level),
            hunger: Int(packet.hunger),
            intimacy: Int(packet.intimacy),
            atk: Int(packet.atk2),
            matk: Int(packet.matk),
            hit: Int(packet.hit),
            critical: Int(packet.crit),
            def: Int(packet.def),
            mdef: Int(packet.mdef),
            flee: Int(packet.flee),
            attackMotion: Int(packet.amotion),
            hp: Int(packet.hp),
            maxHP: Int(packet.maxHp),
            sp: Int(packet.sp),
            maxSP: Int(packet.maxSp),
            exp: packet.exp,
            expNext: packet.expNext,
            skillPoints: Int(packet.skillPoints),
            attackRange: Int(packet.range)
        )
    }

    private func homunculusSkill(from packet: PACKET_ZC_HOSKILLINFO_LIST_sub) -> HomunculusState.Skill {
        HomunculusState.Skill(
            id: Int(packet.id),
            identifier: packet.name,
            level: Int(packet.level),
            spCost: Int(packet.sp),
            range: Int(packet.range),
            isUpgradable: packet.upgradable != 0
        )
    }

    // MARK: - Helpers

    private func requirePet() -> Bool {
        guard companions.pet.isActive else {
            addCompanionMessage("You have no pet out.", type: .error)
            return false
        }
        return true
    }

    private func addCompanionMessage(_ content: String, type: MessageCenter.MessageType = .info) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}
