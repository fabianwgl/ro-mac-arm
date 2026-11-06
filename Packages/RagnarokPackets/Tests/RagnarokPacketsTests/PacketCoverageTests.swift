//
//  PacketCoverageTests.swift
//  RagnarokPacketsTests
//
//  Counts how much of rAthena's packet set at PACKETVER 20211103 the client covers.
//  Run Tools/packet-golden/coverage.sh to write docs/port/packet-coverage.md from these numbers.
//
//  GPL-3.0, derived from rAthena.
//

import Foundation
import XCTest
@testable import RagnarokPackets

private typealias G = RathenaGolden20211103

/// rAthena's packet set as the generated golden data describes it, compared with the client.
struct PacketCoverage {
    enum Direction {
        case clientToServer
        case serverToClient
        /// No parse function, no HEADER_* name, no comment naming it.
        case unattributed
        /// Names of both directions share the opcode.
        case ambiguous
    }

    enum Server: String, CaseIterable {
        case login = "login (CA_, AC_)"
        case char = "char (CH_, HC_)"
        case map = "map (CZ_, ZC_)"
        case other = "other (PING, SC_, CT_, TC_)"
        case unnamed = "unnamed raw opcode"
    }

    /// The PacketFactory builders: (PACKET type, rAthena parse function), read from the doc comments by coverage.sh.
    var factory: [(packet: String, function: String)] = []

    let tableByOpcode = Dictionary(uniqueKeysWithValues: G.packets.map { ($0.opcode, $0) })
    let headerNames: [Int: [String]] = Dictionary(grouping: G.headerValues.keys, by: { G.headerValues[$0]! }).mapValues { $0.sorted() }

    /// Every opcode rAthena knows: packet table plus HEADER_* constants.
    var allOpcodes: [Int] {
        Set(tableByOpcode.keys).union(headerNames.keys).sorted()
    }

    /// HEADER_* names without the prefix, plus the name rAthena's comments give, if no constant names it.
    func names(_ opcode: Int) -> [String] {
        let constants = (headerNames[opcode] ?? []).map { String($0.dropFirst("HEADER_".count)) }
        if !constants.isEmpty {
            return constants
        }
        return G.nameHints[opcode].map { [$0] } ?? []
    }

    static func isClientToServer(_ name: String) -> Bool {
        ["CZ_", "CA_", "CH_", "CT_", "CS_"].contains { name.hasPrefix($0) }
    }

    static func isServerToClient(_ name: String) -> Bool {
        ["ZC_", "AC_", "HC_", "SC_", "TC_"].contains { name.hasPrefix($0) }
    }

    func direction(_ opcode: Int) -> Direction {
        if tableByOpcode[opcode]?.function != nil {
            return .clientToServer
        }
        let names = names(opcode)
        let c2s = names.contains(where: Self.isClientToServer)
        let s2c = names.contains(where: Self.isServerToClient)
        switch (c2s, s2c) {
        case (true, false): return .clientToServer
        case (false, true): return .serverToClient
        case (true, true): return .ambiguous
        case (false, false): return names.isEmpty ? .unattributed : .serverToClient
        }
    }

    func server(_ opcode: Int) -> Server {
        for name in names(opcode) {
            if name.hasPrefix("CA_") || name.hasPrefix("AC_") { return .login }
            if name.hasPrefix("CH_") || name.hasPrefix("HC_") { return .char }
            if name.hasPrefix("CZ_") || name.hasPrefix("ZC_") { return .map }
        }
        return names(opcode).isEmpty ? .unnamed : .other
    }

    /// True when rAthena's own sources mention the opcode or one of its names outside the packet tables (heuristic).
    func isReferenced(_ opcode: Int) -> Bool {
        G.opcodesReferencedBySources.contains(opcode)
    }

    /// Server to client packets rAthena can send: named S2C packets, plus table-only packets without a name
    /// that its sources mention.
    var serverToClient: [Int] {
        allOpcodes.filter { opcode in
            switch direction(opcode) {
            case .serverToClient: true
            case .unattributed: isReferenced(opcode)
            default: false
            }
        }
    }

    var unreferencedRawServerToClient: [Int] {
        allOpcodes.filter { direction($0) == .unattributed && !isReferenced($0) }
    }

    var registered: Set<Int> {
        Set(registeredPackets.keys.map { Int(UInt16(bitPattern: $0)) })
    }

    var clientTable: Set<Int> {
        Set(packetDatabase.entriesByPacketType.keys.map { Int(UInt16(bitPattern: $0)) })
    }

    // MARK: Area grouping

    /// Rough feature area of a packet from its name, for the list of packets the client cannot decode.
    static func area(of names: [String]) -> String {
        let name = names.joined(separator: " ")
        let areas: [(String, [String])] = [
            ("Login and char server", ["AC_", "HC_", "CH_", "CA_", "SC_", "TC_", "CT_"]),
            ("Guild and clan", ["GUILD", "GUILD_", "CLAN", "EMBLEM", "ALLY", "HOSTILE", "AGIT", "CASTLE"]),
            ("Party and party booking", ["PARTY", "GROUP", "BOOKING"]),
            ("Homunculus, mercenary, elemental, pet", ["HOM", "MER_", "MERC", "ELEMENTAL", "_PET", "PET_", "PROPERTY_PET", "CAPTURE", "FEED_"]),
            ("Mail, RODEX and auction", ["MAIL", "RODEX", "AUCTION", "BANK"]),
            ("Cash shop and sales", ["CASH", "SE_", "SALE", "BARGAIN", "NPC_MARKET", "BARTER", "STYLING", "PCBANG"]),
            ("Player shops and NPC trade", ["STORE", "VENDING", "BUYING", "MCSTORE", "PURCHASE", "SELL", "ENTRY", "SEARCH_STORE", "OPENSTORE", "DEALTYPE", "EXCHANGE"]),
            ("Items, equipment, storage, cart, refine", ["ITEM", "EQUIP", "STORAGE", "CART", "INVENTORY", "REFIN", "ENCHANT", "REFORM", "MAKING", "MAKABLE", "REPAIR", "CARD", "COMPOSITION", "IDENTIFY", "OPTION", "MERGE", "ARROW", "WEAPON", "WEAR", "TAKEOFF", "DELETE_ITEM", "ADD_ITEM", "PICKUP", "THROW", "GRADE", "RANDOM_ENCHANT", "KAFRA", "SPRITE"]),
            ("Skills, effects and status icons", ["SKILL", "SPELL", "MAGIC", "EFFECT", "AUTOSPELL", "WARPLIST", "MSG_STATE", "STATE_CHANGE", "BLADESTOP", "COMBODELAY", "DISPEL", "MSG_COLOR", "ATTACK", "ACTION", "HIT", "REMEMBER_WARPPOINT", "CASTING", "USESKILL", "GROUNDSKILL", "SELECT_REQUEST", "TOUSESKILL"]),
            ("Quests, achievements, hunting", ["QUEST", "ACH_", "ACHIEVEMENT", "HUNTING", "MISSION"]),
            ("Battleground, battlefield, PvP", ["BATTLE", "PVP", "DUEL", "KILLER", "BG_", "BATTLEFIELD"]),
            ("Rankings and statistics", ["RANK", "POINT", "TAEKWON", "BLACKSMITH", "ALCHEMIST"]),
            ("Roulette, lucky, minigames", ["ROULETTE", "LUCKY", "ADVENTURER"]),
            ("Chat, whisper, friends, messages", ["CHAT", "WHISPER", "FRIEND", "BROADCAST", "MESSAGE", "TALKBOX", "NPC_CHAT", "MSG", "SAY", "WAIT_DIALOG", "NOTIFY_MANNER", "MANNER"]),
            ("NPC dialogs and scripts", ["NPC", "DIALOG", "MENU", "EDITDLG", "SCRIPT", "CLOSE_DIALOG", "PROGRESS", "BROWSER"]),
            ("Character status and parameters", ["STATUS", "PAR_", "PAR4", "PARAM", "STAT", "EXP", "LEVEL", "TRAIT", "COUPLE", "DIVORCE", "WEIGHT", "OVERWEIGHT", "PENALTY", "RESURRECTION", "HP_", "SP_", "UPDATE_", "SHORTCUT", "HOTKEY", "CONFIG", "MAPPROPERTY", "MAPINFO", "SETTING"]),
            ("World, movement and units", ["MOVE", "WARP", "MAP", "NAVI", "CAMERA", "FALL", "SPAWN", "VANISH", "STOP", "WALK", "UNIT", "GRAFFITI", "DISAPPEAR", "DIRECTION", "NOTIFY_", "USER_COUNT", "AID", "TIME", "SOUND", "COMPASS", "ROLE", "ACCEPT", "REFUSE", "RESTART", "DISCONNECT", "QUIT", "PING", "CHANGE", "BLADE", "SHOW", "UI_", "CLOSE", "OPEN"]),
        ]
        for (area, keywords) in areas where keywords.contains(where: { name.contains($0) }) {
            return area
        }
        return "Other"
    }

    // MARK: Report

    func markdown() -> String {
        var out = ""
        func line(_ text: String = "") { out += text + "\n" }
        func opcodeText(_ opcode: Int) -> String { "0x" + String(format: "%04x", opcode) }

        // --- numbers
        let all = allOpcodes
        let tableOpcodes = Set(G.packets.map(\.opcode))
        let parsed = G.packets.filter { $0.function != nil }
        let parsedFunctions = Set(parsed.compactMap(\.function))
        let parsedCurrent = parsed.filter(\.isCurrent)
        let clientTable = clientTable
        let registered = registered

        let c2sOpcodes = all.filter { direction($0) == .clientToServer }
        let s2cNamed = all.filter { direction($0) == .serverToClient }
        let s2c = serverToClient
        let unattributed = all.filter { direction($0) == .unattributed }
        let ambiguous = all.filter { direction($0) == .ambiguous }
        let unreferenced = unreferencedRawServerToClient

        let s2cDecodable = s2c.filter { registered.contains($0) }
        let s2cFramed = s2c.filter { clientTable.contains($0) || registered.contains($0) }
        let s2cNotDecodable = s2c.filter { !registered.contains($0) }
        let s2cNotFramed = s2c.filter { !clientTable.contains($0) && !registered.contains($0) }

        let missingFromClientTable = G.packets.filter { !clientTable.contains($0.opcode) }
        let superseded = missingFromClientTable.filter { $0.function != nil && !$0.isCurrent }
        let clientOnlyTable = clientTable.subtracting(tableOpcodes)

        let factoryFunctions = Set(factory.map(\.function))
        let factoryPackets = Set(factory.map(\.packet))
        let parsedFunctionsCovered = parsedFunctions.intersection(factoryFunctions)
        let loginCharFactory = factory.filter { $0.packet.hasPrefix("PACKET_CA_") || $0.packet.hasPrefix("PACKET_CH_") || $0.packet == "PACKET_PING" }

        let loginCharParsedHeaders = G.headerValues.keys.filter { $0.hasPrefix("HEADER_CA_") || $0.hasPrefix("HEADER_CH_") }

        line("# Packet coverage, PACKETVER \(G.packetVersion)")
        line()
        line("Generated by `Tools/packet-golden/coverage.sh`. Do not edit by hand.")
        line()
        line("- rAthena commit: `\(G.commit)`, PACKETVER `\(G.packetVersion)` (RE), obfuscation not considered.")
        line("- Sources of the numbers: the rAthena headers compiled by `Tools/packet-golden/generate.sh`")
        line("  (`Golden/RathenaGolden20211103.swift`) and the client's `packetDatabase`, `registeredPackets` and `PacketFactory`.")
        line()
        line("## How to regenerate")
        line()
        line("```sh")
        line("Tools/packet-golden/generate.sh /path/to/rathena   # only when rAthena or the client structs changed")
        line("Tools/packet-golden/coverage.sh                    # runs PacketCoverageTests and rewrites this file")
        line("```")
        line()
        line("`generate.sh` needs `clang++` and the rAthena checkout at the pinned commit. `coverage.sh` needs `swift`.")
        line()
        line("## Definitions")
        line()
        line("- **Packet table**: `clif_packetdb.hpp` plus `clif_shuffle.hpp` as the map server builds `packet_db`. It also lists")
        line("  login and char opcodes, because the client protocol is one namespace. It holds every packet rAthena *parses*")
        line("  on the map server, but only some of the packets it *sends*: most server to client packets are written from")
        line("  `PACKET_ZC_*` structs and never enter the table.")
        line("- **Known packets**: the union of the packet table and the `HEADER_*` constants of `src/map/packets.hpp` and")
        line("  `src/common/packets.hpp`.")
        line("- **Direction**: a packet with a parse function is client to server. Otherwise the `HEADER_*` name prefix decides")
        line("  (`CZ_ CA_ CH_ CT_` client to server, `ZC_ AC_ HC_ SC_ TC_` server to client), then the name rAthena's comments give.")
        line("  Packets with no name at all are *unattributed*.")
        line("- **Sendable server to client**: named server to client packets, plus unattributed table entries that rAthena's sending code")
        line("  (`clif.cpp`, `char_clif.cpp`, `loginclif.cpp`, live code at this PACKETVER, found by preprocessing with `-fdirectives-only`)")
        line("  uses: an opcode literal on a line that writes a packet type, or a `HEADER_*` name, or an enumerator registered in the table.")
        line("- **Frameable**: the client knows the length (client packet table, or a registered type), so the stream stays in sync.")
        line("  **Decodable**: a type is registered in `registeredPackets`. A packet that is neither makes `PacketDecoder` throw")
        line("  `unknownPacket` and drop the buffered bytes.")
        line()
        line("## Headline numbers")
        line()
        line("| Metric | Count |")
        line("|---|---:|")
        line("| rAthena known packets (table or `HEADER_*`) | \(all.count) |")
        line("| rAthena packet table entries | \(G.packets.count) |")
        line("| `HEADER_*` constants | \(G.headerValues.count) |")
        line("| `PACKET_*` and helper structs (`sizeof` known) | \(G.rathenaStructSizes.count) |")
        line("| client to server packets | \(c2sOpcodes.count) |")
        line("| server to client, named | \(s2cNamed.count) |")
        line("| server to client, unattributed table entries | \(unattributed.count) (\(unattributed.count - unreferenced.count) mentioned in rAthena sources, \(unreferenced.count) not) |")
        line("| opcodes with names of both directions | \(ambiguous.count) |")
        line("| **server to client sendable** | **\(s2c.count)** |")
        line("| of which the client can frame (length known) | \(s2cFramed.count) |")
        line("| of which the client can decode (`registeredPackets`) | \(s2cDecodable.count) |")
        line("| of which the client cannot frame (decoder throws `unknownPacket`) | \(s2cNotFramed.count) |")
        line("| client packet table entries | \(clientTable.count) |")
        line("| client decoders in `registeredPackets` | \(registered.count) |")
        line("| **client to server packets rAthena parses on the map server (parse function)** | **\(parsed.count)** opcodes, \(parsedCurrent.count) current, \(parsedFunctions.count) distinct functions |")
        line("| login and char packets rAthena defines `HEADER_CA_*` or `HEADER_CH_*` for | \(loginCharParsedHeaders.count) |")
        line("| **`PacketFactory` builders** | **\(factory.count)** for \(factoryPackets.count) packet types |")
        line("| rAthena parse functions covered by a `PacketFactory` builder | \(parsedFunctionsCovered.count) of \(parsedFunctions.count) |")
        line("| `PacketFactory` builders for login and char packets | \(loginCharFactory.count) |")
        line()
        line("### Per server, by packet name prefix")
        line()
        line("| Server | known packets | client to server | server to client sendable | decodable |")
        line("|---|---:|---:|---:|---:|")
        for server in Server.allCases {
            let known = all.filter { self.server($0) == server }
            let c2sCount = known.filter { direction($0) == .clientToServer }.count
            let s2cOfServer = s2c.filter { self.server($0) == server }
            line("| \(server.rawValue) | \(known.count) | \(c2sCount) | \(s2cOfServer.count) | \(s2cOfServer.filter { registered.contains($0) }.count) |")
        }
        line()
        line("The login and char servers dispatch their packets with their own `switch` and have no table, so their rows count")
        line("`HEADER_*` constants only. The one raw packet they parse without a constant (`CH_ENTER`, 0x0065) is in the unnamed row.")
        line()
        line("### Client packet table against rAthena's")
        line()
        line("- rAthena table: \(G.packets.count) entries. Client table: \(clientTable.count) entries, \(clientTable.intersection(tableOpcodes).count) of them in rAthena's table.")
        line("- \(missingFromClientTable.count) rAthena entries are not in the client table: \(superseded.count) are older opcodes of client packets that were renumbered")
        line("  (rAthena keeps them, the client keeps only the newest opcode per parse function), \(missingFromClientTable.count - superseded.count) are not explained.")
        line("- \(clientOnlyTable.count) client entries are not in rAthena's table: \(clientOnlyTable.sorted().map(opcodeText).joined(separator: ", ")) (`clif_navigateTo`, added by hand).")
        line("- Fixed lengths and offsets of every shared entry are compared by `GoldenPacketTests`.")
        line()

        // --- registered packets with no evidence
        let unverified = registered.sorted().filter { opcode in
            let typeName = registeredPackets.first(where: { Int(UInt16(bitPattern: $0.key)) == opcode }).map { String(describing: $0.value) } ?? ""
            return tableByOpcode[opcode] == nil && G.rathenaStructSizes[typeName] == nil
        }
        line("### Decoders checked against rAthena")
        line()
        line("`GoldenPacketTests.testRegisteredPacketsMatchRathena` checks a decoder's length against the `PACKET_*` struct of the same name,")
        line("or rAthena's packet table, and that the type's `HEADER_*` constant has the registered opcode.")
        line("\(registered.count - unverified.count) of \(registered.count) registered decoders have a struct or a table entry to compare with.")
        if unverified.isEmpty {
            line("Byte level golden packets cover \(G.blobs.keys.filter(Self.isServerToClient).count) of them, see `GoldenPacketTests`.")
        } else {
            line("The other \(unverified.count) are hand written types for packets rAthena writes with raw `WFIFOx` calls, nothing to compare with:")
            line()
            let unverifiedNames = unverified.map { opcode in
                let type = registeredPackets.first(where: { Int(UInt16(bitPattern: $0.key)) == opcode }).map { String(describing: $0.value) } ?? "?"
                return "`\(type)` \(opcodeText(opcode))"
            }
            line(unverifiedNames.joined(separator: ", "))
        }
        line()
        line("The client also has \(G.clientOnlyStructs.count) sized structs without a same-named struct in rAthena at this PACKETVER")
        line("(hand written in `Packets/`, or generated for other versions): \(G.clientOnlyStructs.map { "`\($0)`" }.joined(separator: ", ")).")
        line()

        // --- the list
        line("## Server to client packets the client cannot decode")
        line()
        line("\(s2cNotDecodable.count) of the \(s2c.count) sendable server to client packets have no registered decoder.")
        line("\(s2cNotDecodable.count - s2cNotFramed.count) of them are at least framed (length in the client table, logged and skipped), the other \(s2cNotFramed.count) are marked **no length**:")
        line("they are the ones that break the stream.")
        line()
        line("Names come from `HEADER_*` constants, or from the comments above rAthena's `clif_*` functions (marked `~`, they can describe an")
        line("older use of a reused opcode). `*` marks unattributed table entries that rAthena's sources mention.")
        line()

        var groups: [String: [Int]] = [:]
        for opcode in s2cNotDecodable {
            groups[Self.area(of: names(opcode)), default: []].append(opcode)
        }
        for area in groups.keys.sorted(by: { lhs, rhs in
            if lhs == "Other" { return false }
            if rhs == "Other" { return true }
            return lhs < rhs
        }) {
            let opcodes = groups[area]!
            line("### \(area) (\(opcodes.count))")
            line()
            for opcode in opcodes {
                let constants = (headerNames[opcode] ?? []).map { String($0.dropFirst("HEADER_".count)) }
                let label: String
                if !constants.isEmpty {
                    label = constants.joined(separator: ", ")
                } else if let hint = G.nameHints[opcode] {
                    label = "~\(hint)"
                } else {
                    label = "unnamed*"
                }
                let length = tableByOpcode[opcode].map { $0.length == -1 ? "variable" : "\($0.length) bytes" }
                let framing = clientTable.contains(opcode) ? "length known" : "**no length**"
                line("- `\(opcodeText(opcode))` \(label)\(length.map { ", table \($0)" } ?? ""), \(framing)")
            }
            line()
        }

        if !unreferenced.isEmpty {
            line("## Table entries excluded from \"sendable\"")
            line()
            line("\(unreferenced.count) unnamed table entries without a parse function whose opcode rAthena's sources never mention. They are")
            line("most likely legacy lines of the table that nothing sends:")
            line()
            line(unreferenced.map(opcodeText).joined(separator: " "))
            line()
        }
        return out
    }
}

final class PacketCoverageTests: XCTestCase {
    /// Parses `PACKET_X=clif_function` pairs separated by commas, as coverage.sh extracts them from PacketFactory.swift.
    private func factoryFromEnvironment() -> [(packet: String, function: String)] {
        guard let value = ProcessInfo.processInfo.environment["PACKET_FACTORY"] else { return [] }
        return value.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: "=")
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
    }

    func testPacketCoverageReport() throws {
        var coverage = PacketCoverage()
        coverage.factory = factoryFromEnvironment()

        XCTAssertFalse(coverage.allOpcodes.isEmpty)
        XCTAssertFalse(coverage.serverToClient.isEmpty)

        if let path = ProcessInfo.processInfo.environment["PACKET_COVERAGE_OUTPUT"] {
            let markdown = coverage.markdown()
            try markdown.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
