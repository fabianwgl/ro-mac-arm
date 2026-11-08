//
//  PacketFactory.swift
//  RagnarokNetwork
//
//  Created by Leon Li on 2026/1/9.
//

import Foundation
import RagnarokConstants
import RagnarokModels
import RagnarokPackets

public enum PacketFactory {

    // MARK: - CA (Client → Login Server)

    /// | `PACKET_CA_LOGIN` | `logclif_parse_reqauth_raw` |
    public static func CA_LOGIN(username: String, password: String) -> PACKET_CA_LOGIN {
        var packet = PACKET_CA_LOGIN()
        packet.packetType = HEADER_CA_LOGIN
        packet.version = 0
        packet.username = username
        packet.password = password
        packet.clienttype = 0
        return packet
    }

    /// | `PACKET_CA_CONNECT_INFO_CHANGED` | `logclif_parse_keepalive` |
    public static func CA_CONNECT_INFO_CHANGED(username: String) -> PACKET_CA_CONNECT_INFO_CHANGED {
        var packet = PACKET_CA_CONNECT_INFO_CHANGED()
        packet.packetType = HEADER_CA_CONNECT_INFO_CHANGED
        packet.name = username
        return packet
    }

    // MARK: - CH (Client → Char Server)

    /// | `PACKET_CH_ENTER` | `chclif_parse_reqtoconnect` |
    public static func CH_ENTER(account: AccountInfo) -> PACKET_CH_ENTER {
        var packet = PACKET_CH_ENTER()
        packet.packetType = HEADER_CH_ENTER
        packet.accountID = account.accountID
        packet.loginID1 = account.loginID1
        packet.loginID2 = account.loginID2
        packet.clientType = account.langType
        packet.sex = UInt8(account.sex)
        return packet
    }

    /// | `PACKET_CH_SELECT_CHAR` | `chclif_parse_charselect` |
    public static func CH_SELECT_CHAR(slot: Int) -> PACKET_CH_SELECT_CHAR {
        var packet = PACKET_CH_SELECT_CHAR()
        packet.packetType = HEADER_CH_SELECT_CHAR
        packet.slot = UInt8(slot)
        return packet
    }

    /// | `PACKET_CH_MAKE_CHAR` | `chclif_parse_createnewchar` |
    public static func CH_MAKE_CHAR(character: CharacterInfo) -> PACKET_CH_MAKE_CHAR {
        var packet = PACKET_CH_MAKE_CHAR()
        packet.packetType = HEADER_CH_MAKE_CHAR
        packet.name = character.name
        packet.slot = UInt8(character.charNum)
        packet.hair_color = UInt16(character.headPalette)
        packet.hair_style = UInt16(character.head)
        packet.job = UInt32(character.job)
        packet.sex = UInt8(character.sex)
        return packet
    }

    /// | `PACKET_CH_DELETE_CHAR3_RESERVED` | `chclif_parse_char_delete2_req` |
    public static func CH_DELETE_CHAR3_RESERVED(charID: UInt32) -> PACKET_CH_DELETE_CHAR3_RESERVED {
        var packet = PACKET_CH_DELETE_CHAR3_RESERVED()
        packet.packetType = HEADER_CH_DELETE_CHAR3_RESERVED
        packet.CID = charID
        return packet
    }

    /// | `PACKET_CH_DELETE_CHAR3` | `chclif_parse_char_delete2_accept` |
    public static func CH_DELETE_CHAR3(charID: UInt32, birthdate: String) -> PACKET_CH_DELETE_CHAR3 {
        var packet = PACKET_CH_DELETE_CHAR3()
        packet.packetType = HEADER_CH_DELETE_CHAR3
        packet.CID = charID
        packet.birthdate = birthdate
        return packet
    }

    /// | `PACKET_CH_SECOND_PASSWD_ACK` | `chclif_parse_pincode_check` |
    public static func CH_SECOND_PASSWD_ACK(accountID: UInt32, encryptedPin: String) -> PACKET_CH_SECOND_PASSWD_ACK {
        var packet = PACKET_CH_SECOND_PASSWD_ACK()
        packet.packetType = HEADER_CH_SECOND_PASSWD_ACK
        packet.AID = accountID
        packet.pin = encryptedPin
        return packet
    }

    /// | `PACKET_CH_MAKE_SECOND_PASSWD` | `chclif_parse_pincode_setnew` |
    public static func CH_MAKE_SECOND_PASSWD(accountID: UInt32, encryptedPin: String) -> PACKET_CH_MAKE_SECOND_PASSWD {
        var packet = PACKET_CH_MAKE_SECOND_PASSWD()
        packet.packetType = HEADER_CH_MAKE_SECOND_PASSWD
        packet.AID = accountID
        packet.pin = encryptedPin
        return packet
    }

    /// | `PACKET_CH_EDIT_SECOND_PASSWD` | `chclif_parse_pincode_change` |
    public static func CH_EDIT_SECOND_PASSWD(accountID: UInt32, encryptedOldPin: String, encryptedNewPin: String) -> PACKET_CH_EDIT_SECOND_PASSWD {
        var packet = PACKET_CH_EDIT_SECOND_PASSWD()
        packet.packetType = HEADER_CH_EDIT_SECOND_PASSWD
        packet.AID = accountID
        packet.old_pin = encryptedOldPin
        packet.new_pin = encryptedNewPin
        return packet
    }

    /// | `PACKET_PING` | `chclif_parse_keepalive` |
    public static func PING(accountID: UInt32) -> PACKET_PING {
        var packet = PACKET_PING()
        packet.packetType = HEADER_PING
        packet.AID = accountID
        return packet
    }

    // MARK: - CZ (Client → Map Server)

    /// | `PACKET_CZ_ENTER` | `clif_parse_LoadEndAck` |
    public static func CZ_ENTER(account: AccountInfo, charID: UInt32) -> PACKET_CZ_ENTER {
        var packet = PACKET_CZ_ENTER()
        packet.accountID = account.accountID
        packet.charID = charID
        packet.loginID1 = account.loginID1
        packet.clientTime = UInt32(Date.now.timeIntervalSince1970)
        packet.sex = UInt8(account.sex)
        return packet
    }

    /// | `PACKET_CZ_REQUEST_MOVE` | `clif_parse_WalkToXY` |
    public static func CZ_REQUEST_MOVE(position: SIMD2<Int>) -> PACKET_CZ_REQUEST_MOVE {
        var packet = PACKET_CZ_REQUEST_MOVE()
        packet.x = Int16(position.x)
        packet.y = Int16(position.y)
        return packet
    }

    /// | `PACKET_CZ_NOTIFY_ACTORINIT` | `clif_parse_LoadEndAck` |
    public static func CZ_NOTIFY_ACTORINIT() -> PACKET_CZ_NOTIFY_ACTORINIT {
        var packet = PACKET_CZ_NOTIFY_ACTORINIT()
        packet.packetType = HEADER_CZ_NOTIFY_ACTORINIT
        return packet
    }

    /// | `PACKET_CZ_RESTART` | `clif_parse_Restart` |
    public static func CZ_RESTART(type: UInt8) -> PACKET_CZ_RESTART {
        var packet = PACKET_CZ_RESTART()
        packet.type = type
        return packet
    }

    /// | `PACKET_CZ_STANDING_RESURRECTION` | `clif_parse_AutoRevive` |
    public static func CZ_STANDING_RESURRECTION() -> PACKET_CZ_STANDING_RESURRECTION {
        let packet = PACKET_CZ_STANDING_RESURRECTION()
        return packet
    }

    /// | `PACKET_CZ_REQUEST_QUIT` | `clif_parse_QuitGame` |
    public static func CZ_REQUEST_QUIT() -> PACKET_CZ_REQUEST_QUIT {
        var packet = PACKET_CZ_REQUEST_QUIT()
        packet.packetType = HEADER_CZ_REQUEST_QUIT
        return packet
    }

    /// | `PACKET_CZ_REQUEST_TIME` | `clif_keepalive` |
    public static func CZ_REQUEST_TIME(clientTime: UInt32) -> PACKET_CZ_REQUEST_TIME {
        var packet = PACKET_CZ_REQUEST_TIME()
        packet.clientTime = clientTime
        return packet
    }

    /// | `PACKET_CZ_REQUEST_ACT` | `clif_parse_ActionRequest` |
    public static func CZ_REQUEST_ACT(targetID: UInt32, actionType: DamageType) -> PACKET_CZ_REQUEST_ACT {
        var packet = PACKET_CZ_REQUEST_ACT()
        packet.targetID = targetID
        packet.action = UInt8(actionType.rawValue)
        return packet
    }

    /// | `PACKET_CZ_CHANGE_DIRECTION` | `clif_parse_ChangeDir` |
    public static func CZ_CHANGE_DIRECTION(headDirection: UInt16, direction: UInt8) -> PACKET_CZ_CHANGE_DIRECTION {
        var packet = PACKET_CZ_CHANGE_DIRECTION()
        packet.headDirection = headDirection
        packet.direction = direction
        return packet
    }

    /// | `PACKET_CZ_STATUS_CHANGE` | `clif_parse_StatusUp` |
    public static func CZ_STATUS_CHANGE(property: StatusProperty, amount: Int) -> PACKET_CZ_STATUS_CHANGE {
        var packet = PACKET_CZ_STATUS_CHANGE()
        packet.statusID = Int16(property.rawValue)
        packet.amount = Int8(amount)
        return packet
    }

    /// | `PACKET_CZ_ADVANCED_STATUS_CHANGE` | `clif_parse_traitstatus_up` |
    public static func CZ_ADVANCED_STATUS_CHANGE(property: StatusProperty, amount: Int) -> PACKET_CZ_ADVANCED_STATUS_CHANGE {
        var packet = PACKET_CZ_ADVANCED_STATUS_CHANGE()
        packet.packetType = HEADER_CZ_ADVANCED_STATUS_CHANGE
        packet.type = Int16(property.rawValue)
        packet.amount = Int16(amount)
        return packet
    }

    /// | `PACKET_CZ_REQUEST_CHAT` | `clif_parse_GlobalMessage` |
    public static func CZ_REQUEST_CHAT(message: String) -> PACKET_CZ_REQUEST_CHAT {
        var packet = PACKET_CZ_REQUEST_CHAT()
        packet.message = message
        return packet
    }

    /// | `PACKET_CZ_WHISPER` | `clif_parse_WisMessage` |
    public static func CZ_WHISPER(receiver: String, message: String) -> PACKET_CZ_WHISPER {
        var packet = PACKET_CZ_WHISPER()
        packet.packetType = HEADER_CZ_WHISPER
        packet.packetLength = Int16(2 + 2 + 24 + message.utf8.count)
        packet.receiver = receiver
        packet.message = message
        return packet
    }

    /// | `PACKET_CZ_REQUEST_CHAT_PARTY` | `clif_parse_PartyMessage` |
    public static func CZ_REQUEST_CHAT_PARTY(message: String) -> PACKET_CZ_REQUEST_CHAT_PARTY {
        var packet = PACKET_CZ_REQUEST_CHAT_PARTY()
        packet.packetType = HEADER_CZ_REQUEST_CHAT_PARTY
        packet.packetLength = Int16(2 + 2 + message.utf8.count)
        packet.message = message
        return packet
    }

    /// | `PACKET_CZ_GUILD_CHAT` | `clif_parse_GuildMessage` |
    public static func CZ_GUILD_CHAT(message: String) -> PACKET_CZ_GUILD_CHAT {
        var packet = PACKET_CZ_GUILD_CHAT()
        packet.packetType = HEADER_CZ_GUILD_CHAT
        packet.packetLength = Int16(2 + 2 + message.utf8.count)
        packet.message = message
        return packet
    }

    /// | `PACKET_CZ_ITEM_PICKUP` | `clif_parse_TakeItem` |
    public static func CZ_ITEM_PICKUP(objectID: UInt32) -> PACKET_CZ_ITEM_PICKUP {
        var packet = PACKET_CZ_ITEM_PICKUP()
        packet.objectID = objectID
        return packet
    }

    /// | `PACKET_CZ_USE_ITEM` | `clif_parse_UseItem` |
    public static func CZ_USE_ITEM(index: Int, accountID: UInt32) -> PACKET_CZ_USE_ITEM {
        var packet = PACKET_CZ_USE_ITEM()
        packet.index = UInt16(index)
        packet.accountID = accountID
        return packet
    }

    /// | `PACKET_CZ_REQ_WEAR_EQUIP` | `clif_parse_EquipItem` |
    public static func CZ_REQ_WEAR_EQUIP(index: Int, location: EquipPositions) -> PACKET_CZ_REQ_WEAR_EQUIP {
        var packet = PACKET_CZ_REQ_WEAR_EQUIP()
        packet.packetType = HEADER_CZ_REQ_WEAR_EQUIP
        packet.index = UInt16(index)
        packet.position = UInt32(location.rawValue)
        return packet
    }

    /// | `PACKET_CZ_REQ_TAKEOFF_EQUIP` | `clif_parse_UnequipItem` |
    public static func CZ_REQ_TAKEOFF_EQUIP(index: Int) -> PACKET_CZ_REQ_TAKEOFF_EQUIP {
        var packet = PACKET_CZ_REQ_TAKEOFF_EQUIP()
        packet.index = UInt16(index)
        return packet
    }

    /// | `PACKET_CZ_ITEM_THROW` | `clif_parse_DropItem` |
    public static func CZ_ITEM_THROW(index: Int, amount: Int) -> PACKET_CZ_ITEM_THROW {
        var packet = PACKET_CZ_ITEM_THROW()
        packet.index = UInt16(index)
        packet.amount = Int16(amount)
        return packet
    }

    /// | `PACKET_CZ_UPGRADE_SKILLLEVEL` | `clif_parse_SkillUp` |
    public static func CZ_UPGRADE_SKILLLEVEL(skillID: Int) -> PACKET_CZ_UPGRADE_SKILLLEVEL {
        var packet = PACKET_CZ_UPGRADE_SKILLLEVEL()
        packet.skillId = UInt16(skillID)
        return packet
    }

    /// | `PACKET_CZ_USE_SKILL` | `clif_parse_UseSkillToId` |
    public static func CZ_USE_SKILL(skillID: Int, selectedLevel: Int, targetID: UInt32) -> PACKET_CZ_USE_SKILL {
        var packet = PACKET_CZ_USE_SKILL()
        packet.selectedLevel = UInt16(selectedLevel)
        packet.skillId = UInt16(skillID)
        packet.targetId = targetID
        return packet
    }

    /// | `PACKET_CZ_USE_SKILL_TOGROUND` | `clif_parse_UseSkillToPos` |
    public static func CZ_USE_SKILL_TOGROUND(skillID: Int, selectedLevel: Int, position: SIMD2<Int>) -> PACKET_CZ_USE_SKILL_TOGROUND {
        var packet = PACKET_CZ_USE_SKILL_TOGROUND()
        packet.selectedLevel = UInt16(selectedLevel)
        packet.skillId = UInt16(skillID)
        packet.xPos = Int16(position.x)
        packet.yPos = Int16(position.y)
        return packet
    }

    /// | `PACKET_CZ_SELECT_WARPPOINT` | `clif_parse_UseSkillMap` |
    public static func CZ_SELECT_WARPPOINT(skillID: Int, mapName: String) -> PACKET_CZ_SELECT_WARPPOINT {
        var packet = PACKET_CZ_SELECT_WARPPOINT()
        packet.packetType = HEADER_CZ_SELECT_WARPPOINT
        packet.skill_id = Int16(skillID)
        packet.mapname = mapName
        return packet
    }

    /// | `PACKET_CZ_SHORTCUT_KEY_CHANGE2` | `clif_parse_Hotkey` |
    public static func CZ_SHORTCUT_KEY_CHANGE2(change: ShortcutChange) -> PACKET_CZ_SHORTCUT_KEY_CHANGE2 {
        var packet = PACKET_CZ_SHORTCUT_KEY_CHANGE2()
        packet.packetType = HEADER_CZ_SHORTCUT_KEY_CHANGE2
        packet.tab = 0
        packet.index = UInt16(change.index)
        packet.hotkey = hotkey_data(from: change.shortcut)
        return packet
    }

    /// | `PACKET_CZ_SHORTCUTKEYBAR_ROTATE2` | `clif_parse_HotkeyRowShift` |
    public static func CZ_SHORTCUTKEYBAR_ROTATE2(rowShift: Int) -> PACKET_CZ_SHORTCUTKEYBAR_ROTATE2 {
        var packet = PACKET_CZ_SHORTCUTKEYBAR_ROTATE2()
        packet.packetType = HEADER_CZ_SHORTCUTKEYBAR_ROTATE2
        packet.tab = 0
        packet.rowshift = UInt8(rowShift)
        return packet
    }

    /// | `PACKET_CZ_CONTACTNPC` | `clif_parse_NpcClicked` |
    public static func CZ_CONTACTNPC(npcID: UInt32) -> PACKET_CZ_CONTACTNPC {
        var packet = PACKET_CZ_CONTACTNPC()
        packet.packetType = HEADER_CZ_CONTACTNPC
        packet.AID = npcID
        packet.type = 1
        return packet
    }

    /// | `PACKET_CZ_REQ_NEXT_SCRIPT` | `clif_parse_NpcNextClicked` |
    public static func CZ_REQ_NEXT_SCRIPT(npcID: UInt32) -> PACKET_CZ_REQ_NEXT_SCRIPT {
        var packet = PACKET_CZ_REQ_NEXT_SCRIPT()
        packet.packetType = HEADER_CZ_REQ_NEXT_SCRIPT
        packet.npcID = npcID
        return packet
    }

    /// | `PACKET_CZ_CLOSE_DIALOG` | `clif_parse_NpcCloseClicked` |
    public static func CZ_CLOSE_DIALOG(npcID: UInt32) -> PACKET_CZ_CLOSE_DIALOG {
        var packet = PACKET_CZ_CLOSE_DIALOG()
        packet.packetType = HEADER_CZ_CLOSE_DIALOG
        packet.GID = npcID
        return packet
    }

    /// | `PACKET_CZ_CHOOSE_MENU` | `clif_parse_NpcSelectMenu` |
    public static func CZ_CHOOSE_MENU(npcID: UInt32, select: UInt8) -> PACKET_CZ_CHOOSE_MENU {
        var packet = PACKET_CZ_CHOOSE_MENU()
        packet.packetType = HEADER_CZ_CHOOSE_MENU
        packet.npcID = npcID
        packet.select = select
        return packet
    }

    /// | `PACKET_CZ_INPUT_EDITDLG` | `clif_parse_NpcAmountInput` |
    public static func CZ_INPUT_EDITDLG(npcID: UInt32, value: Int32) -> PACKET_CZ_INPUT_EDITDLG {
        var packet = PACKET_CZ_INPUT_EDITDLG()
        packet.packetType = HEADER_CZ_INPUT_EDITDLG
        packet.GID = npcID
        packet.value = value
        return packet
    }

    /// | `PACKET_CZ_INPUT_EDITDLGSTR` | `clif_parse_NpcStringInput` |
    public static func CZ_INPUT_EDITDLGSTR(npcID: UInt32, value: String) -> PACKET_CZ_INPUT_EDITDLGSTR {
        var packet = PACKET_CZ_INPUT_EDITDLGSTR()
        packet.packetType = HEADER_CZ_INPUT_EDITDLGSTR
        packet.packetLength = Int16(2 + 2 + 4 + value.utf8.count)
        packet.GID = Int32(npcID)
        packet.value = value
        return packet
    }

    /// | `PACKET_CZ_ACK_SELECT_DEALTYPE` | `clif_parse_NpcBuySellSelected` |
    public static func CZ_ACK_SELECT_DEALTYPE(npcID: UInt32, dealType: NPCShopDealType) -> PACKET_CZ_ACK_SELECT_DEALTYPE {
        var packet = PACKET_CZ_ACK_SELECT_DEALTYPE()
        packet.packetType = HEADER_CZ_ACK_SELECT_DEALTYPE
        packet.GID = npcID
        packet.type = dealType.rawValue
        return packet
    }

    /// | `PACKET_CZ_PC_PURCHASE_ITEMLIST` | `clif_parse_NpcBuyListSend` |
    public static func CZ_PC_PURCHASE_ITEMLIST(purchases: [NPCShopPurchase]) -> PACKET_CZ_PC_PURCHASE_ITEMLIST {
        var packet = PACKET_CZ_PC_PURCHASE_ITEMLIST()
        packet.packetType = 0xc8
        packet.packetLength = Int16(2 + 2 + purchases.count * PACKET_CZ_PC_PURCHASE_ITEMLIST_sub.size)
        packet.items = purchases.map { purchase in
            var item = PACKET_CZ_PC_PURCHASE_ITEMLIST_sub()
            item.amount = UInt16(purchase.amount)
            item.itemId = UInt32(purchase.itemID)
            return item
        }
        return packet
    }

    /// | `PACKET_CZ_PC_SELL_ITEMLIST` | `clif_parse_NpcSellListSend` |
    public static func CZ_PC_SELL_ITEMLIST(sales: [NPCShopSale]) -> PACKET_CZ_PC_SELL_ITEMLIST {
        var packet = PACKET_CZ_PC_SELL_ITEMLIST()
        packet.packetType = HEADER_CZ_PC_SELL_ITEMLIST
        packet.packetLength = Int16(2 + 2 + sales.count * PACKET_CZ_PC_SELL_ITEMLIST_sub.size)
        packet.sellList = sales.map { sale in
            var item = PACKET_CZ_PC_SELL_ITEMLIST_sub()
            item.index = UInt16(sale.index)
            item.amount = UInt16(sale.amount)
            return item
        }
        return packet
    }

    /// | `PACKET_CZ_NPC_TRADE_QUIT` | `clif_parse_NPCShopClosed` |
    public static func CZ_NPC_TRADE_QUIT() -> PACKET_CZ_NPC_TRADE_QUIT {
        var packet = PACKET_CZ_NPC_TRADE_QUIT()
        packet.packetType = HEADER_CZ_NPC_TRADE_QUIT
        return packet
    }

    /// | `PACKET_CZ_MOVE_ITEM_FROM_BODY_TO_STORE` | `clif_parse_MoveToKafra` |
    public static func CZ_MOVE_ITEM_FROM_BODY_TO_STORE(index: Int, amount: Int) -> PACKET_CZ_MOVE_ITEM_FROM_BODY_TO_STORE {
        var packet = PACKET_CZ_MOVE_ITEM_FROM_BODY_TO_STORE()
        packet.index = UInt16(index)
        packet.amount = Int32(amount)
        return packet
    }

    /// | `PACKET_CZ_MOVE_ITEM_FROM_STORE_TO_BODY` | `clif_parse_MoveFromKafra` |
    public static func CZ_MOVE_ITEM_FROM_STORE_TO_BODY(index: Int, amount: Int) -> PACKET_CZ_MOVE_ITEM_FROM_STORE_TO_BODY {
        var packet = PACKET_CZ_MOVE_ITEM_FROM_STORE_TO_BODY()
        packet.index = UInt16(index)
        packet.amount = Int32(amount)
        return packet
    }

    /// | `PACKET_CZ_CLOSE_STORE` | `clif_parse_CloseKafra` |
    public static func CZ_CLOSE_STORE() -> PACKET_CZ_CLOSE_STORE {
        let packet = PACKET_CZ_CLOSE_STORE()
        return packet
    }

    /// | `PACKET_CZ_PING_LIVE` | `clif_parse_dull` |
    public static func CZ_PING_LIVE() -> PACKET_CZ_PING_LIVE {
        var packet = PACKET_CZ_PING_LIVE()
        packet.packetType = HEADER_CZ_PING_LIVE
        return packet
    }

    /// | `PACKET_CZ_ACTIVE_QUEST` | `clif_parse_questStateAck` |
    public static func CZ_ACTIVE_QUEST(questID: UInt32, active: Bool) -> PACKET_CZ_ACTIVE_QUEST {
        var packet = PACKET_CZ_ACTIVE_QUEST()
        packet.packetType = HEADER_CZ_ACTIVE_QUEST
        packet.quest_id = questID
        packet.active = active ? 1 : 0
        return packet
    }

    /// | `PACKET_CZ_MAKE_GROUP2` | `clif_parse_CreateParty2` |
    public static func CZ_MAKE_GROUP2(
        name: String,
        itemPickup: Bool = false,
        itemShare: Bool = false
    ) -> PACKET_CZ_MAKE_GROUP2 {
        var packet = PACKET_CZ_MAKE_GROUP2()
        packet.packetType = HEADER_CZ_MAKE_GROUP2
        packet.name = name
        packet.item_pickup = itemPickup ? 1 : 0
        packet.item_share = itemShare ? 1 : 0
        return packet
    }

    /// | `PACKET_CZ_PARTY_JOIN_REQ` | `clif_parse_PartyInvite2` |
    public static func CZ_PARTY_JOIN_REQ(name: String) -> PACKET_CZ_PARTY_JOIN_REQ {
        var packet = PACKET_CZ_PARTY_JOIN_REQ()
        packet.packetType = HEADER_CZ_PARTY_JOIN_REQ
        packet.name = name
        return packet
    }

    /// | `PACKET_CZ_PARTY_JOIN_REQ_ACK` | `clif_parse_ReplyPartyInvite2` |
    public static func CZ_PARTY_JOIN_REQ_ACK(partyID: UInt32, accept: Bool) -> PACKET_CZ_PARTY_JOIN_REQ_ACK {
        var packet = PACKET_CZ_PARTY_JOIN_REQ_ACK()
        packet.packetType = HEADER_CZ_PARTY_JOIN_REQ_ACK
        packet.party_id = partyID
        packet.flag = accept ? 0 : 1
        return packet
    }

    /// | `PACKET_CZ_REQ_LEAVE_GROUP` | `clif_parse_LeaveParty` |
    public static func CZ_REQ_LEAVE_GROUP() -> PACKET_CZ_REQ_LEAVE_GROUP {
        var packet = PACKET_CZ_REQ_LEAVE_GROUP()
        packet.packetType = HEADER_CZ_REQ_LEAVE_GROUP
        return packet
    }

    /// | `PACKET_CZ_REQ_EXPEL_GROUP_MEMBER` | `clif_parse_RemovePartyMember` |
    public static func CZ_REQ_EXPEL_GROUP_MEMBER(accountID: UInt32, name: String) -> PACKET_CZ_REQ_EXPEL_GROUP_MEMBER {
        var packet = PACKET_CZ_REQ_EXPEL_GROUP_MEMBER()
        packet.packetType = HEADER_CZ_REQ_EXPEL_GROUP_MEMBER
        packet.AID = accountID
        packet.name = name
        return packet
    }

    /// | `PACKET_CZ_CHANGE_GROUP_MASTER` | `clif_parse_PartyChangeLeader` |
    public static func CZ_CHANGE_GROUP_MASTER(accountID: UInt32) -> PACKET_CZ_CHANGE_GROUP_MASTER {
        var packet = PACKET_CZ_CHANGE_GROUP_MASTER()
        packet.packetType = HEADER_CZ_CHANGE_GROUP_MASTER
        packet.AID = accountID
        return packet
    }

    /// | `PACKET_CZ_ADD_FRIENDS` | `clif_parse_FriendsListAdd` |
    public static func CZ_ADD_FRIENDS(name: String) -> PACKET_CZ_ADD_FRIENDS {
        var packet = PACKET_CZ_ADD_FRIENDS()
        packet.packetType = HEADER_CZ_ADD_FRIENDS
        packet.name = name
        return packet
    }

    /// | `PACKET_CZ_ACK_REQ_ADD_FRIENDS` | `clif_parse_FriendsListReply` |
    public static func CZ_ACK_REQ_ADD_FRIENDS(
        accountID: UInt32,
        characterID: UInt32,
        accept: Bool
    ) -> PACKET_CZ_ACK_REQ_ADD_FRIENDS {
        var packet = PACKET_CZ_ACK_REQ_ADD_FRIENDS()
        packet.packetType = HEADER_CZ_ACK_REQ_ADD_FRIENDS
        packet.AID = accountID
        packet.CID = characterID
        packet.flag = accept ? 0 : 1
        return packet
    }

    /// | `PACKET_CZ_DELETE_FRIENDS` | `clif_parse_FriendsListRemove` |
    public static func CZ_DELETE_FRIENDS(accountID: UInt32, characterID: UInt32) -> PACKET_CZ_DELETE_FRIENDS {
        var packet = PACKET_CZ_DELETE_FRIENDS()
        packet.packetType = HEADER_CZ_DELETE_FRIENDS
        packet.AID = accountID
        packet.CID = characterID
        return packet
    }

    /// | `PACKET_CZ_OPEN_UI` | `clif_parse_open_ui` |
    public static func CZ_OPEN_UI(uiType: Int8) -> PACKET_CZ_OPEN_UI {
        var packet = PACKET_CZ_OPEN_UI()
        packet.packetType = HEADER_CZ_OPEN_UI
        packet.UIType = uiType
        return packet
    }

    /// | `PACKET_CZ_REQ_CHECK_ATTENDANCE` | `clif_parse_attendance_request` |
    public static func CZ_REQ_CHECK_ATTENDANCE() -> PACKET_CZ_REQ_CHECK_ATTENDANCE {
        PACKET_CZ_REQ_CHECK_ATTENDANCE()
    }

    /// | `PACKET_CZ_REQ_MAKE_GUILD` | `clif_parse_CreateGuild` |
    public static func CZ_REQ_MAKE_GUILD(characterID: UInt32, name: String) -> PACKET_CZ_REQ_MAKE_GUILD {
        var packet = PACKET_CZ_REQ_MAKE_GUILD()
        packet.packetType = HEADER_CZ_REQ_MAKE_GUILD
        packet.GID = characterID
        packet.guildName = name
        return packet
    }

    /// | `PACKET_CZ_REQ_GUILD_MENUINTERFACE` | `clif_parse_GuildCheckMaster` |
    public static func CZ_REQ_GUILD_MENUINTERFACE() -> PACKET_CZ_REQ_GUILD_MENUINTERFACE {
        var packet = PACKET_CZ_REQ_GUILD_MENUINTERFACE()
        packet.packetType = HEADER_CZ_REQ_GUILD_MENUINTERFACE
        return packet
    }

    /// | `PACKET_CZ_REQ_GUILD_MENU` | `clif_parse_GuildRequestInfo` |
    public static func CZ_REQ_GUILD_MENU(type: Int32) -> PACKET_CZ_REQ_GUILD_MENU {
        var packet = PACKET_CZ_REQ_GUILD_MENU()
        packet.packetType = HEADER_CZ_REQ_GUILD_MENU
        packet.type = type
        return packet
    }

    /// | `PACKET_CZ_REQ_JOIN_GUILD2` | `clif_parse_GuildInvite2` |
    public static func CZ_REQ_JOIN_GUILD2(name: String) -> PACKET_CZ_REQ_JOIN_GUILD2 {
        var packet = PACKET_CZ_REQ_JOIN_GUILD2()
        packet.packetType = HEADER_CZ_REQ_JOIN_GUILD2
        packet.name = name
        return packet
    }

    /// | `PACKET_CZ_JOIN_GUILD` | `clif_parse_GuildReplyInvite` |
    public static func CZ_JOIN_GUILD(guildID: UInt32, accept: Bool) -> PACKET_CZ_JOIN_GUILD {
        var packet = PACKET_CZ_JOIN_GUILD()
        packet.packetType = HEADER_CZ_JOIN_GUILD
        packet.guild_id = guildID
        packet.answer = accept ? 1 : 0
        return packet
    }

    /// | `PACKET_CZ_REQ_LEAVE_GUILD` | `clif_parse_GuildLeave` |
    public static func CZ_REQ_LEAVE_GUILD(
        guildID: UInt32,
        accountID: UInt32,
        characterID: UInt32,
        reason: String
    ) -> PACKET_CZ_REQ_LEAVE_GUILD {
        var packet = PACKET_CZ_REQ_LEAVE_GUILD()
        packet.packetType = HEADER_CZ_REQ_LEAVE_GUILD
        packet.guild_id = guildID
        packet.AID = accountID
        packet.CID = characterID
        packet.message = reason
        return packet
    }

    /// | `PACKET_CZ_REQ_BAN_GUILD` | `clif_parse_GuildExpulsion` |
    public static func CZ_REQ_BAN_GUILD(
        guildID: UInt32,
        accountID: UInt32,
        characterID: UInt32,
        reason: String
    ) -> PACKET_CZ_REQ_BAN_GUILD {
        var packet = PACKET_CZ_REQ_BAN_GUILD()
        packet.packetType = HEADER_CZ_REQ_BAN_GUILD
        packet.guild_id = guildID
        packet.AID = accountID
        packet.CID = characterID
        packet.message = reason
        return packet
    }

    /// | `PACKET_CZ_REQ_DISORGANIZE_GUILD` | `clif_parse_GuildBreak` |
    public static func CZ_REQ_DISORGANIZE_GUILD(key: String) -> PACKET_CZ_REQ_DISORGANIZE_GUILD {
        var packet = PACKET_CZ_REQ_DISORGANIZE_GUILD()
        packet.packetType = HEADER_CZ_REQ_DISORGANIZE_GUILD
        packet.key = key
        return packet
    }

    /// | `PACKET_CZ_GUILD_NOTICE` | `clif_parse_GuildChangeNotice` |
    public static func CZ_GUILD_NOTICE(guildID: UInt32, subject: String, notice: String) -> PACKET_CZ_GUILD_NOTICE {
        var packet = PACKET_CZ_GUILD_NOTICE()
        packet.packetType = HEADER_CZ_GUILD_NOTICE
        packet.guildID = guildID
        packet.subject = subject
        packet.notice = notice
        return packet
    }

    /// | `PACKET_CZ_COMMAND_PET` | `clif_parse_PetMenu` |
    public static func CZ_COMMAND_PET(command: PACKET_CZ_COMMAND_PET.Command) -> PACKET_CZ_COMMAND_PET {
        var packet = PACKET_CZ_COMMAND_PET()
        packet.command = command.rawValue
        return packet
    }

    /// | `PACKET_CZ_RENAME_PET` | `clif_parse_ChangePetName` |
    public static func CZ_RENAME_PET(name: String) -> PACKET_CZ_RENAME_PET {
        var packet = PACKET_CZ_RENAME_PET()
        packet.name = name
        return packet
    }

    /// | `PACKET_CZ_SELECT_PETEGG` | `clif_parse_SelectEgg` |
    public static func CZ_SELECT_PETEGG(index: UInt16) -> PACKET_CZ_SELECT_PETEGG {
        var packet = PACKET_CZ_SELECT_PETEGG()
        packet.index = index
        return packet
    }

    /// | `PACKET_CZ_COMMAND_MER` | `clif_parse_HomMenu` |
    public static func CZ_COMMAND_MER(command: PACKET_CZ_COMMAND_MER.Command) -> PACKET_CZ_COMMAND_MER {
        var packet = PACKET_CZ_COMMAND_MER()
        packet.command = command.rawValue
        return packet
    }

    /// | `PACKET_CZ_RENAME_MER` | `clif_parse_ChangeHomunculusName` |
    public static func CZ_RENAME_MER(name: String) -> PACKET_CZ_RENAME_MER {
        var packet = PACKET_CZ_RENAME_MER()
        packet.name = name
        return packet
    }

    /// | `PACKET_CZ_REQUEST_MOVETOOWNER` | `clif_parse_HomMoveToMaster` |
    public static func CZ_REQUEST_MOVETOOWNER(objectID: UInt32) -> PACKET_CZ_REQUEST_MOVETOOWNER {
        var packet = PACKET_CZ_REQUEST_MOVETOOWNER()
        packet.GID = objectID
        return packet
    }

    /// | `PACKET_CZ_CONFIG` | `clif_parse_configuration` |
    public static func CZ_CONFIG(type: PACKET_CZ_CONFIG.ConfigType, enabled: Bool) -> PACKET_CZ_CONFIG {
        var packet = PACKET_CZ_CONFIG()
        packet.type = type.rawValue
        packet.flag = enabled ? 1 : 0
        return packet
    }

    /// | `PACKET_CZ_REQ_ACH_REWARD` | `clif_parse_AchievementCheckReward` |
    public static func CZ_REQ_ACH_REWARD(achievementID: UInt32) -> PACKET_CZ_REQ_ACH_REWARD {
        var packet = PACKET_CZ_REQ_ACH_REWARD()
        packet.packetType = HEADER_CZ_REQ_ACH_REWARD
        packet.achievementID = achievementID
        return packet
    }

    // MARK: RODEX
    //
    // The opcodes are the ones rAthena parses at PACKETVER 20211103, see RodexHeaders.swift.
    // `openType` is the tab of the mail: 0 normal, 1 account, 2 returned.

    /// | `PACKET_CZ_REQ_OPEN_MAIL` | `clif_parse_Mail_refreshinbox` |
    public static func CZ_REQ_OPEN_MAIL() -> PACKET_CZ_REQ_OPEN_MAIL {
        var packet = PACKET_CZ_REQ_OPEN_MAIL()
        packet.packetType = HEADER_CZ_OPEN_MAILBOX2
        return packet
    }

    /// | `PACKET_CZ_REQ_REFRESH_MAIL_LIST` | `clif_parse_Mail_refreshinbox` |
    public static func CZ_REQ_REFRESH_MAIL_LIST() -> PACKET_CZ_REQ_REFRESH_MAIL_LIST {
        var packet = PACKET_CZ_REQ_REFRESH_MAIL_LIST()
        packet.packetType = HEADER_CZ_REQ_REFRESH_MAIL_LIST2
        return packet
    }

    /// | `PACKET_CZ_REQ_NEXT_MAIL_LIST` | `clif_parse_Mail_refreshinbox` |
    public static func CZ_REQ_NEXT_MAIL_LIST(openType: UInt8, lastMailID: Int64) -> PACKET_CZ_REQ_NEXT_MAIL_LIST {
        var packet = PACKET_CZ_REQ_NEXT_MAIL_LIST()
        packet.packetType = HEADER_CZ_REQ_NEXT_MAIL_LIST
        packet.opentype = Int8(bitPattern: openType)
        packet.Lower_MailID = lastMailID
        return packet
    }

    /// | `PACKET_CZ_CLOSE_MAILBOX` | `clif_parse_dull` |
    public static func CZ_CLOSE_MAILBOX() -> PACKET_CZ_CLOSE_MAILBOX {
        PACKET_CZ_CLOSE_MAILBOX()
    }

    /// | `PACKET_CZ_REQ_READ_MAIL` | `clif_parse_Mail_read` |
    public static func CZ_REQ_READ_MAIL(openType: UInt8, mailID: Int64) -> PACKET_CZ_REQ_READ_MAIL {
        var packet = PACKET_CZ_REQ_READ_MAIL()
        packet.packetType = HEADER_CZ_REQ_READ_MAIL
        packet.opentype = Int8(bitPattern: openType)
        packet.MailID = mailID
        return packet
    }

    /// | `PACKET_CZ_REQ_ZENY_FROM_MAIL` | `clif_parse_Mail_getattach` |
    public static func CZ_REQ_ZENY_FROM_MAIL(openType: UInt8, mailID: Int64) -> PACKET_CZ_REQ_ZENY_FROM_MAIL {
        var packet = PACKET_CZ_REQ_ZENY_FROM_MAIL()
        packet.packetType = HEADER_CZ_REQ_ZENY_FROM_MAIL
        packet.MailID = mailID
        packet.opentype = Int8(bitPattern: openType)
        return packet
    }

    /// | `PACKET_CZ_REQ_ITEM_FROM_MAIL` | `clif_parse_Mail_getattach` |
    public static func CZ_REQ_ITEM_FROM_MAIL(openType: UInt8, mailID: Int64) -> PACKET_CZ_REQ_ITEM_FROM_MAIL {
        var packet = PACKET_CZ_REQ_ITEM_FROM_MAIL()
        packet.packetType = HEADER_CZ_REQ_ITEM_FROM_MAIL
        packet.MailID = mailID
        packet.opentype = Int8(bitPattern: openType)
        return packet
    }

    /// | `PACKET_CZ_REQ_DELETE_MAIL` | `clif_parse_Mail_delete` |
    public static func CZ_REQ_DELETE_MAIL(openType: UInt8, mailID: Int64) -> PACKET_CZ_REQ_DELETE_MAIL {
        var packet = PACKET_CZ_REQ_DELETE_MAIL()
        packet.packetType = HEADER_CZ_REQ_DELETE_MAIL
        packet.opentype = Int8(bitPattern: openType)
        packet.MailID = mailID
        return packet
    }

    /// | `PACKET_CZ_REQ_OPEN_WRITE_MAIL` | `clif_parse_Mail_beginwrite` |
    public static func CZ_REQ_OPEN_WRITE_MAIL(receiverName: String) -> PACKET_CZ_REQ_OPEN_WRITE_MAIL {
        var packet = PACKET_CZ_REQ_OPEN_WRITE_MAIL()
        packet.packetType = HEADER_CZ_REQ_OPEN_WRITE_MAIL
        packet.receiveName = receiverName
        return packet
    }

    /// | `PACKET_CZ_REQ_CANCEL_WRITE_MAIL` | `clif_parse_Mail_cancelwrite` |
    public static func CZ_REQ_CANCEL_WRITE_MAIL() -> PACKET_CZ_REQ_CANCEL_WRITE_MAIL {
        PACKET_CZ_REQ_CANCEL_WRITE_MAIL()
    }

    /// | `PACKET_CZ_CHECKNAME2` | `clif_parse_Mail_Receiver_Check` |
    public static func CZ_CHECKNAME2(name: String, isOwnCharacter: Bool = false) -> PACKET_CZ_CHECKNAME2 {
        var packet = PACKET_CZ_CHECKNAME2()
        packet.packetType = HEADER_CZ_CHECKNAME2
        packet.Name = name
        packet.own_char = isOwnCharacter ? 1 : 0
        return packet
    }

    /// | `PACKET_CZ_ADD_ITEM_TO_MAIL` | `clif_parse_Mail_setattach` |
    public static func CZ_ADD_ITEM_TO_MAIL(index: Int, count: Int) -> PACKET_CZ_ADD_ITEM_TO_MAIL {
        var packet = PACKET_CZ_ADD_ITEM_TO_MAIL()
        packet.packetType = HEADER_CZ_REQ_ADD_ITEM_TO_MAIL
        packet.index = Int16(truncatingIfNeeded: index)
        packet.count = Int16(truncatingIfNeeded: count)
        return packet
    }

    /// | `PACKET_CZ_REQ_REMOVE_ITEM_MAIL` | `clif_parse_Mail_winopen` |
    public static func CZ_REQ_REMOVE_ITEM_MAIL(index: Int, count: Int) -> PACKET_CZ_REQ_REMOVE_ITEM_MAIL {
        var packet = PACKET_CZ_REQ_REMOVE_ITEM_MAIL()
        packet.packetType = HEADER_CZ_REQ_REMOVE_ITEM_MAIL
        packet.index = Int16(truncatingIfNeeded: index)
        packet.cnt = UInt16(truncatingIfNeeded: count)
        return packet
    }

    /// | `PACKET_CZ_SEND_MAIL` | `clif_parse_Mail_send` |
    ///
    /// Title and text go out with a terminating NUL, and both lengths count it, as rAthena's client does.
    /// Items are not part of this packet: they were attached one by one with `CZ_ADD_ITEM_TO_MAIL`.
    public static func CZ_SEND_MAIL(
        receiverName: String,
        senderName: String,
        receiverCharacterID: UInt32,
        zeny: Int64,
        title: String,
        body: String
    ) -> PACKET_CZ_SEND_MAIL {
        let titleLength = title.utf8.count + 1
        let bodyLength = body.utf8.count + 1
        let headerLength = 2 + 2 + 24 + 24 + 8 + 2 + 2 + 4

        var packet = PACKET_CZ_SEND_MAIL()
        packet.packetType = HEADER_CZ_REQ_WRITE_MAIL2
        packet.packetLength = Int16(headerLength + titleLength + bodyLength)
        packet.receiveName = receiverName
        packet.senderName = senderName
        packet.zeny = zeny
        packet.Titlelength = Int16(titleLength)
        packet.TextcontentsLength = Int16(bodyLength)
        packet.receiver_char_id = Int32(bitPattern: receiverCharacterID)
        packet.string = title + "\u{0}" + body + "\u{0}"
        return packet
    }

    // MARK: Vending
    //
    // The opcodes are the ones rAthena parses at PACKETVER 20211103, see VendingHeaders.swift.
    // Cart indices are the ones the server sends, which already count the 2 that the client adds
    // to the cart slot (`client_index` in clif.cpp).

    /// | `PACKET_CZ_REQ_BUY_FROMMC` | `clif_parse_VendingListReq` |
    public static func CZ_REQ_BUY_FROMMC(vendorID: UInt32) -> PACKET_CZ_REQ_BUY_FROMMC {
        PACKET_CZ_REQ_BUY_FROMMC(AID: vendorID)
    }

    /// | `PACKET_CZ_PC_PURCHASE_ITEMLIST_FROMMC2` | `clif_parse_PurchaseReq2` |
    ///
    /// `shopID` is the `venderId` of the item list the shop sent, rAthena refuses the purchase when the
    /// shop was closed and opened again since.
    public static func CZ_PC_PURCHASE_ITEMLIST_FROMMC2(
        vendorID: UInt32,
        shopID: UInt32,
        purchases: [(index: Int, count: Int)]
    ) -> PACKET_CZ_PC_PURCHASE_ITEMLIST_FROMMC2 {
        var packet = PACKET_CZ_PC_PURCHASE_ITEMLIST_FROMMC2()
        packet.packetType = HEADER_CZ_PC_PURCHASE_ITEMLIST_FROMMC2
        packet.packetLength = Int16(2 + 2 + 4 + 4 + purchases.count * CZ_PURCHASE_ITEM_FROMMC.size)
        packet.AID = vendorID
        packet.UniqueID = shopID
        packet.list = purchases.map { purchase in
            var item = CZ_PURCHASE_ITEM_FROMMC()
            item.count = Int16(truncatingIfNeeded: purchase.count)
            item.index = Int16(truncatingIfNeeded: purchase.index)
            return item
        }
        return packet
    }

    /// | `PACKET_CZ_REQ_OPENSTORE2` | `clif_parse_OpenVending` |
    ///
    /// Opens the shop with these items (`index` is the cart index of the server), or cancels the set up
    /// window when `items` is empty. The title is cut to the 79 bytes rAthena keeps (`MESSAGE_SIZE` is 80).
    public static func CZ_REQ_OPENSTORE2(title: String, items: [(index: Int, amount: Int, price: Int)]) -> PACKET_CZ_REQ_OPENSTORE2 {
        let isOpening = !items.isEmpty
        return PACKET_CZ_REQ_OPENSTORE2(
            storeName: isOpening ? truncatedUTF8(title, maxBytes: 79) : "",
            isOpening: isOpening,
            items: items.map { item in
                PACKET_CZ_REQ_OPENSTORE2_sub(
                    index: UInt16(truncatingIfNeeded: item.index),
                    amount: UInt16(truncatingIfNeeded: item.amount),
                    price: UInt32(truncatingIfNeeded: item.price)
                )
            }
        )
    }

    /// | `PACKET_CZ_REQ_CLOSESTORE` | `clif_parse_CloseVending` |
    public static func CZ_REQ_CLOSESTORE() -> PACKET_CZ_REQ_CLOSESTORE {
        PACKET_CZ_REQ_CLOSESTORE()
    }

    private static func truncatedUTF8(_ text: String, maxBytes: Int) -> String {
        var text = text
        while text.utf8.count > maxBytes {
            text.removeLast()
        }
        return text
    }

    /// | `PACKET_CZ_MOVE_ITEM_FROM_BODY_TO_CART` | `clif_parse_PutItemToCart` |
    public static func CZ_MOVE_ITEM_FROM_BODY_TO_CART(index: Int, amount: Int) -> PACKET_CZ_MOVE_ITEM_FROM_BODY_TO_CART {
        var packet = PACKET_CZ_MOVE_ITEM_FROM_BODY_TO_CART()
        packet.packetType = HEADER_CZ_MOVE_ITEM_FROM_BODY_TO_CART
        packet.index = Int16(truncatingIfNeeded: index)
        packet.count = Int32(truncatingIfNeeded: amount)
        return packet
    }

    /// | `PACKET_CZ_MOVE_ITEM_FROM_CART_TO_BODY` | `clif_parse_GetItemFromCart` |
    public static func CZ_MOVE_ITEM_FROM_CART_TO_BODY(index: Int, amount: Int) -> PACKET_CZ_MOVE_ITEM_FROM_CART_TO_BODY {
        var packet = PACKET_CZ_MOVE_ITEM_FROM_CART_TO_BODY()
        packet.packetType = HEADER_CZ_MOVE_ITEM_FROM_CART_TO_BODY
        packet.index = UInt16(truncatingIfNeeded: index)
        packet.amount = Int32(truncatingIfNeeded: amount)
        return packet
    }
}
