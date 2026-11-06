//
//  PacketDatabase.swift
//  RagnarokPackets
//
//  Created by Leon Li on 2024/8/21.
//

let packetDatabase = PacketDatabase()

struct PacketDatabase {
    struct Entry {
        var packetType: Int16
        var packetLength: Int16
        var functionName: String?
        var offsets: [Int] = []
    }

    let entriesByPacketType: [Int16 : PacketDatabase.Entry]

    init() {
        var entriesByPacketType: [Int16 : PacketDatabase.Entry] = [:]

        let add_packet: (Int16, Int, String?, [Int]) -> Void = { packetType, packetLength, functionName, offsets in
            if let functionName {
                if let key = entriesByPacketType.first(where: { $0.value.functionName == functionName })?.key {
                    entriesByPacketType.removeValue(forKey: key)
                }
            }

            let entry = PacketDatabase.Entry(
                packetType: packetType,
                packetLength: Int16(packetLength),
                functionName: functionName,
                offsets: offsets
            )
            entriesByPacketType[packetType] = entry
        }

        add_packets(add_packet)

        /// See `clif_navigateTo`
        add_packet(0x08e2, 27, nil, [])

        // RO Mac Client: server to client packets rAthena d4b8e7b8 sends at PACKETVER 20211103
        // that are missing from the generated table. Without a length the decoder cannot skip
        // them and drops the whole stream. Sizes are rAthena's sizeof (see docs/port/packet-coverage.md).
        add_packet(0x01f2, 20, nil, [])  // ZC_UPDATE_CHARSTAT (party/guild member online state)
        add_packet(0x08fd, 6, nil, [])   // HC_ACK_CHANGE_CHARNAME
        add_packet(0x0b8e, 18, nil, [])  // ZC_REPUTE_OPEN
        add_packet(0x0174, -1, nil, [])  // ZC_ACK_CHANGE_GUILD_POSITIONINFO
        add_packet(0x0156, -1, nil, [])  // ZC_ACK_REQ_CHANGE_MEMBERS
        add_packet(0x0ae3, -1, nil, [])  // TC_RESULT
        add_packet(0x0b70, -1, nil, [])  // HC_ACK_CHANGE_CHARACTER_SLOT

        self.entriesByPacketType = entriesByPacketType
    }

    func entry(forFunctionName functionName: String) -> PacketDatabase.Entry? {
        entriesByPacketType.first(where: { $0.value.functionName == functionName })?.value
    }
}
