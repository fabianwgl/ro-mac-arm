//
//  PlaySession+Social.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokNetwork
import RagnarokPackets

@Observable
final class SocialState {
    var party = Party()
    var friendList = FriendList()
    var partyInvitation: PartyInvitation?
    var friendInvitation: FriendInvitation?
    var denyPartyInvites = false

    @ObservationIgnored var pendingPartyName: String?

    var invitation: SocialInvitation? {
        if let partyInvitation {
            .party(partyInvitation)
        } else if let friendInvitation {
            .friend(friendInvitation)
        } else {
            nil
        }
    }
}

enum SocialInvitation: Identifiable, Equatable, Sendable {
    case party(PartyInvitation)
    case friend(FriendInvitation)

    var id: String {
        switch self {
        case .party(let invitation):
            "party-\(invitation.partyID)"
        case .friend(let invitation):
            "friend-\(invitation.accountID)"
        }
    }
}

extension PlaySession {
    func handleSocialPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_ACK_MAKE_GROUP:
            handleMakeGroup(packet)
        case let packet as PACKET_ZC_PARTY_JOIN_REQ:
            social.partyInvitation = PartyInvitation(
                partyID: packet.GRID,
                partyName: packet.groupName
            )
        case let packet as PACKET_ZC_PARTY_JOIN_REQ_ACK:
            handlePartyJoinRequestAck(packet)
        case let packet as PACKET_ZC_GROUP_LIST:
            let members = packet.members.map(member(from:))
            social.party.apply(name: packet.partyName, memberList: members)
        case let packet as PACKET_ZC_ADD_MEMBER_TO_GROUP:
            social.party.name = packet.partyName
            social.party.sharePickup = packet.sharePickup != 0
            social.party.shareLoot = packet.shareLoot != 0
            social.party.addMember(member(from: packet))
        case let packet as PACKET_ZC_DELETE_MEMBER_FROM_GROUP:
            handleDeleteMemberFromGroup(packet)
        case let packet as PACKET_ZC_GROUP_ISALIVE:
            social.party.setDead(accountID: packet.AID, isDead: packet.isDead != 0)
        case let packet as PACKET_ZC_CHANGE_GROUP_MASTER:
            social.party.setLeader(accountID: packet.AID)
        case let packet as PACKET_ZC_NOTIFY_HP_TO_GROUPM:
            social.party.updateHP(
                accountID: packet.AID,
                hp: Int(packet.hp),
                maxHP: Int(packet.maxhp)
            )
        case let packet as PACKET_ZC_NOTIFY_POSITION_TO_GROUPM:
            social.party.updatePosition(
                accountID: UInt32(bitPattern: packet.AID),
                position: SIMD2(Int(packet.xPos), Int(packet.yPos))
            )
        case let packet as PACKET_ZC_NOTIFY_MEMBERINFO_TO_GROUPM:
            social.party.updateMemberInfo(
                accountID: UInt32(bitPattern: packet.AID),
                job: Int(packet.job),
                baseLevel: Int(packet.level)
            )
        case let packet as PACKET_ZC_PARTY_CONFIG:
            social.denyPartyInvites = packet.denyPartyInvites != 0
        case let packet as PACKET_ZC_FRIENDS_LIST:
            let friends = packet.friends.map { friend in
                FriendList.Friend(
                    accountID: friend.AID,
                    characterID: friend.CID,
                    name: friend.name,
                    isOnline: false
                )
            }
            social.friendList.apply(list: friends)
        case let packet as PACKET_ZC_FRIENDS_STATE:
            social.friendList.setOnline(accountID: packet.AID, isOnline: packet.offline == 0)
        case let packet as PACKET_ZC_REQ_ADD_FRIENDS:
            social.friendInvitation = FriendInvitation(
                accountID: packet.AID,
                characterID: packet.CID,
                name: packet.name
            )
        case let packet as PACKET_ZC_ADD_FRIENDS_LIST:
            handleAddFriendsList(packet)
        case let packet as PACKET_ZC_DELETE_FRIENDS:
            social.friendList.remove(accountID: packet.AID)
        default:
            return false
        }
        return true
    }

    // MARK: - Party Requests

    func createParty(name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            addSocialMessage("Enter a party name.", type: .error)
            return
        }

        social.pendingPartyName = name
        sendPacket(PacketFactory.CZ_MAKE_GROUP2(name: name))
    }

    func inviteToParty(name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            addSocialMessage("Enter a character name.", type: .error)
            return
        }

        sendPacket(PacketFactory.CZ_PARTY_JOIN_REQ(name: name))
    }

    func answerPartyInvitation(accept: Bool) {
        guard let invitation = social.partyInvitation else {
            return
        }

        social.partyInvitation = nil
        sendPacket(PacketFactory.CZ_PARTY_JOIN_REQ_ACK(partyID: UInt32(bitPattern: invitation.partyID), accept: accept))
    }

    func leaveParty() {
        sendPacket(PacketFactory.CZ_REQ_LEAVE_GROUP())
    }

    func expelPartyMember(accountID: UInt32, name: String) {
        sendPacket(PacketFactory.CZ_REQ_EXPEL_GROUP_MEMBER(accountID: accountID, name: name))
    }

    func changePartyLeader(accountID: UInt32) {
        sendPacket(PacketFactory.CZ_CHANGE_GROUP_MASTER(accountID: accountID))
    }

    // MARK: - Friend Requests

    func addFriend(name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            addSocialMessage("Enter a character name.", type: .error)
            return
        }

        sendPacket(PacketFactory.CZ_ADD_FRIENDS(name: name))
    }

    func answerFriendInvitation(accept: Bool) {
        guard let invitation = social.friendInvitation else {
            return
        }

        social.friendInvitation = nil
        sendPacket(PacketFactory.CZ_ACK_REQ_ADD_FRIENDS(
            accountID: invitation.accountID,
            characterID: invitation.characterID,
            accept: accept
        ))
    }

    func removeFriend(accountID: UInt32) {
        guard let friend = social.friendList.friends.first(where: { $0.accountID == accountID }) else {
            return
        }

        sendPacket(PacketFactory.CZ_DELETE_FRIENDS(
            accountID: friend.accountID,
            characterID: friend.characterID
        ))
    }

    // MARK: - Packet Handling

    private func handleMakeGroup(_ packet: PACKET_ZC_ACK_MAKE_GROUP) {
        let pendingPartyName = social.pendingPartyName
        social.pendingPartyName = nil

        switch packet.result {
        case 0:
            if let pendingPartyName {
                social.party = Party(name: pendingPartyName)
            }
            addSocialMessage("Party created.")
        case 1:
            addSocialMessage("You are already in a party.", type: .error)
        case 2:
            addSocialMessage("A party with that name already exists.", type: .error)
        default:
            addSocialMessage("Failed to create a party.", type: .error)
        }
    }

    private func handlePartyJoinRequestAck(_ packet: PACKET_ZC_PARTY_JOIN_REQ_ACK) {
        switch packet.result {
        case 0:
            addSocialMessage("\(packet.characterName) joined the party.")
        case 1:
            addSocialMessage("\(packet.characterName) declined the party invitation.", type: .error)
        case 2:
            addSocialMessage("\(packet.characterName) is offline.", type: .error)
        case 3:
            addSocialMessage("The party is full.", type: .error)
        case 4:
            addSocialMessage("\(packet.characterName) is already in a party.", type: .error)
        default:
            addSocialMessage("Could not invite \(packet.characterName).", type: .error)
        }
    }

    private func handleDeleteMemberFromGroup(_ packet: PACKET_ZC_DELETE_MEMBER_FROM_GROUP) {
        let accountID = UInt32(bitPattern: packet.AID)
        social.party.removeMember(accountID: accountID)

        if accountID == account.accountID {
            social.party.reset()
            addSocialMessage("You left the party.")
        } else if packet.result == 1 {
            addSocialMessage("\(packet.characterName) was expelled from the party.")
        } else {
            addSocialMessage("\(packet.characterName) left the party.")
        }
    }

    private func handleAddFriendsList(_ packet: PACKET_ZC_ADD_FRIENDS_LIST) {
        guard packet.flag == 0 else {
            addSocialMessage("Could not add \(packet.name) as a friend.", type: .error)
            return
        }

        social.friendList.add(FriendList.Friend(
            accountID: packet.AID,
            characterID: packet.CID,
            name: packet.name,
            isOnline: true
        ))
        addSocialMessage("\(packet.name) is now your friend.")
    }

    // MARK: - Packet Conversion

    private func member(from packet: PACKET_ZC_GROUP_LIST_SUB) -> Party.Member {
        Party.Member(
            accountID: packet.AID,
            characterID: packet.GID,
            name: packet.playerName,
            mapName: packet.mapName,
            job: Int(packet.class_),
            baseLevel: Int(packet.baseLevel),
            hp: 0,
            maxHP: 0,
            position: nil,
            isLeader: packet.leader != 0,
            isOnline: packet.offline == 0,
            isDead: false
        )
    }

    private func member(from packet: PACKET_ZC_ADD_MEMBER_TO_GROUP) -> Party.Member {
        Party.Member(
            accountID: packet.AID,
            characterID: packet.GID,
            name: packet.playerName,
            mapName: packet.mapName,
            job: Int(packet.class_),
            baseLevel: Int(packet.baseLevel),
            hp: 0,
            maxHP: 0,
            position: nil,
            isLeader: packet.leader != 0,
            isOnline: packet.offline == 0,
            isDead: false
        )
    }

    private func addSocialMessage(_ content: String, type: MessageCenter.MessageType = .info) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}
