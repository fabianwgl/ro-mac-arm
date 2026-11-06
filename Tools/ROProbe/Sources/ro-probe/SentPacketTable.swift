import Foundation
import RagnarokModels
import RagnarokNetwork
import RagnarokPackets

/// Lengths of the client packets for the login and char servers.
///
/// The packet database is rAthena's map server table, so these opcodes are missing from it. The lengths come
/// from encoding the packets `PacketFactory` builds, which is what `GameSession` sends.
enum SentPacketTable {
    struct Entry {
        var length: Int
        var name: String
    }

    static let entries: [Int: Entry] = {
        var result: [Int: Entry] = [:]
        let encoder = PacketEncoder()
        let account = AccountInfo(from: PACKET_AC_ACCEPT_LOGIN())

        func add(_ packet: some EncodablePacket) {
            guard let data = try? encoder.encode(packet), data.count >= 2 else {
                return
            }
            let opcode = Int(data[data.startIndex]) | Int(data[data.startIndex + 1]) << 8
            result[opcode] = Entry(length: data.count, name: String(describing: type(of: packet)))
        }

        add(PacketFactory.CA_LOGIN(username: "a", password: "b"))
        add(PacketFactory.CA_CONNECT_INFO_CHANGED(username: "a"))
        add(PacketFactory.CH_ENTER(account: account))
        add(PacketFactory.CH_SELECT_CHAR(slot: 0))
        add(PacketFactory.CH_MAKE_CHAR(character: CharacterInfo()))
        add(PacketFactory.CH_DELETE_CHAR3_RESERVED(charID: 0))
        add(PacketFactory.CH_DELETE_CHAR3(charID: 0, birthdate: ""))
        add(PacketFactory.PING(accountID: 0))
        add(PacketFactory.CZ_ENTER(account: account, charID: 0))
        add(PacketFactory.CZ_REQUEST_TIME(clientTime: 0))
        add(PacketFactory.CZ_NOTIFY_ACTORINIT())
        add(PacketFactory.CZ_REQUEST_MOVE(position: .zero))
        add(PacketFactory.CZ_REQUEST_ACT(targetID: 0, actionType: .normal))
        add(PacketFactory.CZ_PING_LIVE())
        return result
    }()
}
