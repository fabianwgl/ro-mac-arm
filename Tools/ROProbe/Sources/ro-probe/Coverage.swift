import Foundation
@testable import RagnarokPackets

/// Packet table coverage for P0-10: how many packets of the 20211103 table the client can decode.
enum Coverage {
    static func compute() -> [String: Any] {
        let database = packetDatabase.entriesByPacketType
        let registered = registeredPackets

        var byPrefix: [String: (total: Int, implemented: Int)] = [:]
        var implementedInDatabase = 0
        var unimplementedNamed: [[String: Any]] = []

        for (type, entry) in database.sorted(by: { UInt16(bitPattern: $0.key) < UInt16(bitPattern: $1.key) }) {
            let opcode = Int(UInt16(bitPattern: type))
            let isImplemented = registered[type] != nil
            if isImplemented {
                implementedInDatabase += 1
            }

            let name = PacketNames.name(for: opcode)
            let prefix = direction(of: name)
            var counts = byPrefix[prefix] ?? (0, 0)
            counts.total += 1
            if isImplemented {
                counts.implemented += 1
            }
            byPrefix[prefix] = counts

            if !isImplemented && prefix.hasSuffix("(server to client)") {
                var item: [String: Any] = ["opcode": "0x" + String(format: "%04x", opcode), "length": Int(entry.packetLength)]
                if let name {
                    item["name"] = name
                }
                if let function = entry.functionName {
                    item["rathenaFunction"] = function
                }
                unimplementedNamed.append(item)
            }
        }

        let registeredNotInTableList: [[String: Any]] = registered
            .filter { database[$0.key] == nil }
            .sorted(by: { UInt16(bitPattern: $0.key) < UInt16(bitPattern: $1.key) })
            .map { ["opcode": "0x" + String(format: "%04x", UInt16(bitPattern: $0.key)), "type": String(describing: $0.value)] }
        let registeredNotInDatabase = registeredNotInTableList.count

        // Every opcode that has a generated HEADER_* constant, split by the direction in its name.
        var namedByDirection: [String: (total: Int, decodable: Int, inTable: Int)] = [:]
        var namedUnimplementedServer: [[String: Any]] = []
        for (opcode, names) in PacketNames.allOpcodes.sorted(by: { $0.key < $1.key }) {
            let type = Int16(truncatingIfNeeded: opcode)
            let group = direction(of: names.joined(separator: " "))
            var counts = namedByDirection[group] ?? (0, 0, 0)
            counts.total += 1
            if registered[type] != nil {
                counts.decodable += 1
            }
            if database[type] != nil {
                counts.inTable += 1
            }
            namedByDirection[group] = counts

            if group.hasPrefix("ZC/AC/HC/SC"), registered[type] == nil {
                namedUnimplementedServer.append([
                    "opcode": "0x" + String(format: "%04x", opcode),
                    "names": names,
                    "inLengthTable": database[type] != nil,
                ])
            }
        }
        var namedGroups: [[String: Any]] = []
        for (group, counts) in namedByDirection.sorted(by: { $0.key < $1.key }) {
            namedGroups.append(["group": group, "distinctOpcodes": counts.total, "decodable": counts.decodable, "inLengthTable": counts.inTable])
        }

        var groups: [[String: Any]] = []
        for (prefix, counts) in byPrefix.sorted(by: { $0.key < $1.key }) {
            groups.append(["group": prefix, "inTable": counts.total, "decodable": counts.implemented])
        }

        return [
            "packetVersion": PACKET_VERSION,
            "tableEntries": database.count,
            "registeredDecodablePackets": registered.count,
            "registeredAndInTable": implementedInDatabase,
            "registeredNotInTable": registeredNotInDatabase,
            "registeredNotInTableList": registeredNotInTableList,
            "groups": groups,
            "namedOpcodeGroups": namedGroups,
            "namedServerToClientWithoutStruct": namedUnimplementedServer,
            "unimplementedServerToClient": unimplementedNamed,
            "namesAvailable": PacketNames.name(for: 0x0087) != nil,
        ]
    }

    /// The generated constants carry the direction in their name prefix.
    private static func direction(of name: String?) -> String {
        guard let name else {
            return "unnamed"
        }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        for prefix in ["ZC_", "AC_", "HC_", "SC_"] where first.contains(prefix) {
            return "ZC/AC/HC/SC (server to client)"
        }
        for prefix in ["CZ_", "CA_", "CH_", "CS_"] where first.contains(prefix) {
            return "CZ/CA/CH (client to server)"
        }
        if first.hasPrefix("packet_") {
            return "rAthena struct packet_* (server to client mostly)"
        }
        return "other"
    }

    static func printSummary(_ coverage: [String: Any]) {
        var lines: [String] = []
        lines.append("==== packet table coverage (PACKETVER \(coverage["packetVersion"] ?? "")) ====")
        lines.append("table entries            \(coverage["tableEntries"] ?? 0)")
        lines.append("registered (decodable)   \(coverage["registeredDecodablePackets"] ?? 0)")
        lines.append("registered and in table  \(coverage["registeredAndInTable"] ?? 0)")
        lines.append("registered not in table  \(coverage["registeredNotInTable"] ?? 0)")
        lines.append("length table entries by name direction:")
        for group in (coverage["groups"] as? [[String: Any]]) ?? [] {
            lines.append("  \(group["group"] ?? ""): \(group["decodable"] ?? 0) of \(group["inTable"] ?? 0) decodable")
        }
        lines.append("generated HEADER_* opcodes by name direction:")
        for group in (coverage["namedOpcodeGroups"] as? [[String: Any]]) ?? [] {
            lines.append("  \(group["group"] ?? ""): \(group["decodable"] ?? 0) of \(group["distinctOpcodes"] ?? 0) decodable, \(group["inLengthTable"] ?? 0) in the length table")
        }
        print(lines.joined(separator: "\n"))
    }
}
