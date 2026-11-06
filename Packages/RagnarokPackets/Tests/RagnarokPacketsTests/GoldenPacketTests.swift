//
//  GoldenPacketTests.swift
//  RagnarokPacketsTests
//
//  Compares the client packet code with data generated from the rAthena headers at the
//  pinned commit (see Tools/packet-golden/generate.sh and Golden/RathenaGolden20211103.swift).
//
//  GPL-3.0, derived from rAthena.
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

private typealias G = RathenaGolden20211103

// MARK: - Mismatch collection

/// One difference between the client and rAthena. `key` identifies it for `knownDifferences`.
struct GoldenProblem {
    var key: String
    var message: String
}

/// Records field level checks of a golden packet and keeps going after the first failure.
final class GoldenChecker {
    let scope: String
    let packet: String
    private(set) var problems: [GoldenProblem] = []

    init(_ scope: String, _ packet: String) {
        self.scope = scope
        self.packet = packet
    }

    func expect<T: Equatable>(_ actual: T, _ expected: T, _ field: String) {
        if actual != expected {
            problems.append(GoldenProblem(key: "\(scope) \(packet) \(field)", message: "\(packet).\(field): client \(actual), rAthena \(expected)"))
        }
    }

    func fail(_ field: String, _ message: String) {
        problems.append(GoldenProblem(key: "\(scope) \(packet) \(field)", message: "\(packet): \(message)"))
    }
}

/// Differences that were looked at and are not client bugs. Every entry needs a reason.
/// A stale entry (one that no longer matches a difference) fails the test, so the list cannot rot.
private let knownDifferences: [String: String] = [
    // rAthena's table lists these server to client packets with the length they had before the
    // item id (and for the sprite change the values) were widened to 32 bits at
    // PACKETVER_RE_NUM >= 20180704. clif.cpp sends sizeof() of the PACKET_ZC_* struct, which
    // is what the client uses (checked by the struct size test), so the wire length is the client's.
    "table 0x01a3 length": "rAthena table says 5, sizeof(PACKET_ZC_FEED_PET) is 7 and is what clif_pet_food sends",
    "table 0x01d7 length": "rAthena table says 11, sizeof(PACKET_ZC_SPRITE_CHANGE) is 15 and is what clif_sprite_change sends",
    "table 0x022f length": "rAthena table says 5, sizeof(PACKET_ZC_FEED_MER) is 7 and is what clif_hom_food sends",
    "table 0x09e6 length": "rAthena table says 22, sizeof(PACKET_ZC_UPDATE_ITEM_FROM_BUYING_STORE) is 24 and is what clif_buyingstore_update_item sends",
    "table 0x0add length": "rAthena table says 22, sizeof(struct packet_dropflooritem) is 24 and is what clif_dropflooritem sends",

    // Variable length packets in rAthena's table (-1) that the client frames with a fixed size. rAthena always
    // writes the length field as sizeof(struct) (clif_set_unit_walking, clif_spawn_unit, clif_idle_unit) or as the
    // constant MAX_GUILDPOSITION * 28 + 4 (clif_guild_positionnamelist), so the fixed size is what is on the wire.
    // It stops being true if rAthena starts to trim these packets.
    "registry 0x0166 length": "ZC_POSITION_ID_NAME_INFO is always sent with all MAX_GUILDPOSITION (20) entries, 564 bytes",
    "registry 0x09fd length": "packet_unit_walking is always sent with PacketLength = sizeof(p) = 114",
    "registry 0x09fe length": "packet_spawn_unit is always sent with PacketLength = sizeof(p) = 107",
    "registry 0x09ff length": "packet_idle_unit is always sent with PacketLength = sizeof(p) = 108",

    // clif_navigateTo sends 0x08e2 with a literal opcode and WFIFOHEAD(fd,27), there is no table entry.
    // PacketDatabase.swift adds it by hand.
    "table 0x08e2 unknown": "clif_navigateTo writes 0x08e2 (27 bytes) without a packet table entry, added by hand in PacketDatabase.swift",
    // Sent from PACKET_* structs (no packet table entry); added to PacketDatabase.swift with rAthena's sizeof
    // so the decoder can skip them instead of dropping the stream.
    "table 0x01f2 unknown": "ZC_UPDATE_CHARSTAT, sizeof 20, sent from its struct",
    "table 0x08fd unknown": "HC_ACK_CHANGE_CHARNAME, sizeof 6, sent from its struct",
    "table 0x0b8e unknown": "ZC_REPUTE_OPEN, sizeof 18, sent from its struct",
    "table 0x0174 unknown": "ZC_ACK_CHANGE_GUILD_POSITIONINFO, variable length, sent from its struct",
    "table 0x0156 unknown": "ZC_ACK_REQ_CHANGE_MEMBERS, variable length, sent from its struct",
    "table 0x0ae3 unknown": "TC_RESULT, variable length, sent from its struct",
    "table 0x0b70 unknown": "HC_ACK_CHANGE_CHARACTER_SLOT, variable length, sent from its struct",
]

// MARK: - Helpers

private func opcode(_ packetType: Int16) -> Int {
    Int(UInt16(bitPattern: packetType))
}

private func hex4(_ opcode: Int) -> String {
    "0x" + String(format: "%04x", opcode)
}

private func goldenData(_ name: String) -> Data {
    guard let hex = G.blobs[name] else {
        preconditionFailure("no golden packet named \(name)")
    }
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        data.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return data
}

private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private func decode<T: DecodablePacket>(_ type: T.Type, from data: Data) throws -> T {
    try T(from: BinaryDecoder(data: data))
}

private func encode(_ packet: some EncodablePacket) throws -> Data {
    try PacketEncoder().encode(packet)
}

final class GoldenPacketTests: XCTestCase {

    /// Fails once with every unexplained problem, and once more for known differences that no longer occur.
    private func report(_ scope: String, _ problems: [GoldenProblem], file: StaticString = #filePath, line: UInt = #line) {
        let unexplained = problems.filter { knownDifferences[$0.key] == nil }
        if !unexplained.isEmpty {
            let list = unexplained.map { "  - \($0.message)" }.joined(separator: "\n")
            XCTFail("\(unexplained.count) \(scope) mismatch(es) against rAthena \(G.commit.prefix(8)) (PACKETVER \(G.packetVersion)):\n\(list)", file: file, line: line)
        }

        let seen = Set(problems.map(\.key))
        let stale = knownDifferences.keys.filter { $0.hasPrefix(scope + " ") && !seen.contains($0) }.sorted()
        if !stale.isEmpty {
            XCTFail("knownDifferences entries that no longer match anything: \(stale.joined(separator: ", "))", file: file, line: line)
        }
    }

    // MARK: - Packet table

    func testPacketTableMatchesRathena() {
        var problems: [GoldenProblem] = []

        let rathena = Dictionary(uniqueKeysWithValues: G.packets.map { ($0.opcode, $0) })
        var clientOpcodes = Set<Int>()

        for (packetType, entry) in packetDatabase.entriesByPacketType.sorted(by: { opcode($0.key) < opcode($1.key) }) {
            let op = opcode(packetType)
            clientOpcodes.insert(op)
            let name = hex4(op)

            guard let expected = rathena[op] else {
                problems.append(GoldenProblem(key: "table \(name) unknown", message: "\(name): client table has a packet (length \(entry.packetLength)) that rAthena's table does not"))
                continue
            }
            if Int(entry.packetLength) != expected.length {
                problems.append(GoldenProblem(key: "table \(name) length", message: "\(name): length client \(entry.packetLength), rAthena \(expected.length)"))
            }
            if entry.functionName != expected.function {
                problems.append(GoldenProblem(key: "table \(name) function", message: "\(name): parse function client \(entry.functionName ?? "none"), rAthena \(expected.function ?? "none")"))
            }
            if entry.offsets != expected.offsets {
                problems.append(GoldenProblem(key: "table \(name) offsets", message: "\(name): offsets client \(entry.offsets), rAthena \(expected.offsets)"))
            }
        }

        // rAthena keeps every older opcode of a client packet that was renumbered (0x72, 0x9b, 0x436, ...
        // all map to clif_parse_WantToConnection). The client keeps only the newest one per parse
        // function, that is intended, so those are not reported as missing.
        let currentOpcodeByFunction = Dictionary(
            G.packets.compactMap { entry in entry.function.flatMap { entry.isCurrent ? ($0, entry.opcode) : nil } },
            uniquingKeysWith: { first, _ in first }
        )
        for expected in G.packets where !clientOpcodes.contains(expected.opcode) {
            if let function = expected.function,
               let current = currentOpcodeByFunction[function],
               clientOpcodes.contains(current),
               packetDatabase.entry(forFunctionName: function)?.packetType == Int16(truncatingIfNeeded: current) {
                continue
            }
            let name = hex4(expected.opcode)
            problems.append(GoldenProblem(key: "table \(name) missing", message: "\(name): in rAthena's table (\(expected.direction.rawValue), length \(expected.length), \(expected.function ?? G.nameHints[expected.opcode] ?? "no name")) but not in the client's"))
        }

        report("table", problems)
    }

    // MARK: - HEADER_* constants

    func testHeaderConstantsMatchRathena() {
        var problems: [GoldenProblem] = []
        let rathenaOpcodes = Set(G.packets.map(\.opcode))

        for (name, client, rathena) in G.clientHeaders {
            if let rathena {
                if client != rathena {
                    problems.append(GoldenProblem(key: "header \(name)", message: "\(name): client \(hex4(client)), rAthena \(hex4(rathena))"))
                }
            } else if !rathenaOpcodes.contains(client) {
                problems.append(GoldenProblem(key: "header \(name)", message: "\(name) = \(hex4(client)): rAthena has no constant of that name and no packet with that opcode"))
            }
        }

        report("header", problems)
    }

    // MARK: - Struct sizes

    func testStructSizesMatchRathena() {
        var problems: [GoldenProblem] = []

        for (name, client, rathena) in G.structSizes where client != -1 {
            if client != rathena {
                problems.append(GoldenProblem(key: "size \(name)", message: "\(name).size: client \(client), sizeof rAthena \(rathena)"))
            }
        }

        report("size", problems)
    }

    /// Every packet the client can decode must have the length rAthena sends and the HEADER_* name its type says.
    /// Evidence, in order: the struct of the same name (what clif.cpp sends), then rAthena's packet table.
    /// Packets with neither (rAthena writes them with raw WFIFOx calls) cannot be checked here, see packet-coverage.md.
    func testRegisteredPacketsMatchRathena() {
        var problems: [GoldenProblem] = []
        let rathena = Dictionary(uniqueKeysWithValues: G.packets.map { ($0.opcode, $0) })

        for (packetType, type) in registeredPackets.sorted(by: { opcode($0.key) < opcode($1.key) }) {
            let op = opcode(packetType)
            let typeName = String(describing: type)
            let label = "\(hex4(op)) \(typeName)"

            // The HEADER_* constant with the type's name must have this opcode.
            let headerName = "HEADER_" + typeName.dropFirst("PACKET_".count)
            if typeName.hasPrefix("PACKET_"), let value = G.headerValues[headerName], value != op {
                problems.append(GoldenProblem(key: "registry \(hex4(op)) header", message: "\(label): registered under \(hex4(op)) but rAthena's \(headerName) is \(hex4(value))"))
            }

            let entry = rathena[op]
            if let function = entry?.function {
                problems.append(GoldenProblem(key: "registry \(hex4(op)) direction", message: "\(label): registered as a server to client packet but rAthena parses it (\(function))"))
            }

            guard let tableLength = entry?.length else { continue }
            if let structSize = G.rathenaStructSizes[typeName], tableLength != -1 {
                // The table can be stale (see the 0x01a3 family in knownDifferences), the struct is what gets sent.
                if type.size != structSize {
                    problems.append(GoldenProblem(key: "registry \(hex4(op)) length", message: "\(label): size client \(type.size), sizeof rAthena \(structSize) (table \(tableLength))"))
                }
            } else if type.size != tableLength {
                problems.append(GoldenProblem(key: "registry \(hex4(op)) length", message: "\(label): size client \(type.size), rAthena table \(tableLength)"))
            }
        }

        report("registry", problems)
    }

    // MARK: - Golden packets, server to client

    private func assertSampleCharacter(_ c: CHARACTER_INFO, _ check: GoldenChecker) {
        check.expect(c.GID, 150000, "GID")
        check.expect(c.exp, 123456789012, "exp")
        check.expect(c.money, 1000, "money")
        check.expect(c.jobexp, 987654321098, "jobexp")
        check.expect(c.joblevel, 50, "joblevel")
        check.expect(c.bodystate, 1, "bodystate")
        check.expect(c.healthstate, 2, "healthstate")
        check.expect(c.effectstate, 3, "effectstate")
        check.expect(c.virtue, 4, "virtue")
        check.expect(c.honor, 5, "honor")
        check.expect(c.jobpoint, 6, "jobpoint")
        check.expect(c.hp, 1000, "hp")
        check.expect(c.maxhp, 2000, "maxhp")
        check.expect(c.sp, 300, "sp")
        check.expect(c.maxsp, 400, "maxsp")
        check.expect(c.speed, 150, "speed")
        check.expect(c.job, 7, "job")
        check.expect(c.head, 11, "head")
        check.expect(c.body, 13, "body")
        check.expect(c.weapon, 1, "weapon")
        check.expect(c.level, 99, "level")
        check.expect(c.sppoint, 3, "sppoint")
        check.expect(c.accessory, 5, "accessory")
        check.expect(c.shield, 2, "shield")
        check.expect(c.accessory2, 6, "accessory2")
        check.expect(c.accessory3, 8, "accessory3")
        check.expect(c.headpalette, 9, "headpalette")
        check.expect(c.bodypalette, 10, "bodypalette")
        check.expect(c.name, "Alice", "name")
        check.expect(c.Str, 21, "Str")
        check.expect(c.Agi, 22, "Agi")
        check.expect(c.Vit, 23, "Vit")
        check.expect(c.Int, 24, "Int")
        check.expect(c.Dex, 25, "Dex")
        check.expect(c.Luk, 26, "Luk")
        check.expect(c.CharNum, 2, "CharNum")
        check.expect(c.hairColor, 3, "hairColor")
        check.expect(c.bIsChangedCharName, 1, "bIsChangedCharName")
        check.expect(c.mapName, "prontera.gat", "mapName")
        check.expect(c.DelRevDate, 1700000000, "DelRevDate")
        check.expect(c.robePalette, 4, "robePalette")
        check.expect(c.chr_slot_changeCnt, 5, "chr_slot_changeCnt")
        check.expect(c.chr_name_changeCnt, 6, "chr_name_changeCnt")
        check.expect(c.sex, 1, "sex")
    }

    /// Framing the way PacketDecoder does it: a registered server to client packet has the fixed length
    /// of its type, or -1 and a length field that covers the whole packet.
    private func checkFraming(_ name: String, _ data: Data, _ check: GoldenChecker) {
        let type = Int16(bitPattern: UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8)
        guard let registered = registeredPackets[type] else {
            check.fail("framing", "\(name) (\(hex4(opcode(type)))) is not registered, the decoder would skip it")
            return
        }
        if registered.size == -1 {
            let length = Int(data[data.startIndex + 2]) | Int(data[data.startIndex + 3]) << 8
            check.expect(length, data.count, "framing length field")
        } else {
            check.expect(registered.size, data.count, "framing fixed length")
        }
    }

    /// Checks `data` decodes to `packet` and, when the client can encode the type, that it encodes back to the same bytes.
    private func checkServerPacket<T: CodablePacket>(_ name: String, _ type: T.Type, roundTrip: Bool = true, _ assertFields: (T, GoldenChecker) -> Void) -> [GoldenProblem] {
        let check = GoldenChecker("golden-s2c", name)
        let data = goldenData(name)
        checkFraming(name, data, check)
        do {
            let packet = try decode(type, from: data)
            assertFields(packet, check)
            if roundTrip {
                let encoded = try encode(packet)
                if encoded != data {
                    check.fail("encode", "re-encoding the decoded packet gives \(hexString(encoded)), rAthena sent \(hexString(data))")
                }
            }
        } catch {
            check.fail("decode", "decoding failed: \(error)")
        }
        return check.problems
    }

    func testServerToClientGoldenPackets() {
        var problems: [GoldenProblem] = []

        problems += checkServerPacket("AC_ACCEPT_LOGIN", PACKET_AC_ACCEPT_LOGIN.self) { p, c in
            c.expect(p.packetType, HEADER_AC_ACCEPT_LOGIN, "packetType")
            c.expect(Int(p.packetLength), 224, "packetLength")
            c.expect(p.login_id1, 0x11223344, "login_id1")
            c.expect(p.AID, 2000001, "AID")
            c.expect(p.login_id2, 0x55667788, "login_id2")
            c.expect(p.last_ip, 0x0100007f, "last_ip")
            c.expect(p.last_login, "2021-11-03 12:34:56", "last_login")
            c.expect(p.sex, 1, "sex")
            c.expect(p.token, "abcdef0123456789", "token")
            c.expect(p.char_servers.count, 1, "char_servers.count")
            if let server = p.char_servers.first {
                c.expect(server.ip, 0x0100007f, "char_servers[0].ip")
                c.expect(server.port, 6121, "char_servers[0].port")
                c.expect(server.name, "rAthena", "char_servers[0].name")
                c.expect(server.users, 5, "char_servers[0].users")
                c.expect(server.type, 3, "char_servers[0].type")
                c.expect(server.new_, 1, "char_servers[0].new_")
                c.expect(server.unknown, [UInt8](repeating: 0, count: 128), "char_servers[0].unknown")
            }
        }

        problems += checkServerPacket("HC_ACCEPT_ENTER", PACKET_HC_ACCEPT_ENTER.self) { p, c in
            c.expect(p.packetType, HEADER_HC_ACCEPT_ENTER, "packetType")
            c.expect(p.total, 12, "total")
            c.expect(p.premium_start, 9, "premium_start")
            c.expect(p.premium_end, 10, "premium_end")
            c.expect(p.extension, "", "extension")
            c.expect(p.characters.count, 1, "characters.count")
            if let character = p.characters.first {
                assertSampleCharacter(character, c)
            }
        }

        problems += checkServerPacket("HC_ACCEPT_ENTER2", PACKET_HC_ACCEPT_ENTER2.self) { p, c in
            c.expect(p.packetType, HEADER_HC_ACCEPT_ENTER2, "packetType")
            c.expect(Int(p.packetLength), 29, "packetLength")
            c.expect(p.normal, 9, "normal")
            c.expect(p.premium, 1, "premium")
            c.expect(p.billing, 2, "billing")
            c.expect(p.producible, 3, "producible")
            c.expect(p.total, 12, "total")
        }

        problems += checkServerPacket("HC_ACK_CHARINFO_PER_PAGE", PACKET_HC_ACK_CHARINFO_PER_PAGE.self) { p, c in
            c.expect(p.packetType, HEADER_HC_ACK_CHARINFO_PER_PAGE, "packetType")
            c.expect(p.characters.count, 1, "characters.count")
            if let character = p.characters.first {
                assertSampleCharacter(character, c)
            }
        }

        problems += checkServerPacket("HC_NOTIFY_ZONESVR", PACKET_HC_NOTIFY_ZONESVR.self) { p, c in
            c.expect(p.packetType, HEADER_HC_NOTIFY_ZONESVR, "packetType")
            c.expect(p.CID, 150000, "CID")
            c.expect(p.mapname, "prontera.gat", "mapname")
            c.expect(p.ip, 0x0100007f, "ip")
            c.expect(p.port, 5121, "port")
            c.expect(p.domain, "ro.example.org", "domain")
        }

        problems += checkServerPacket("HC_SECOND_PASSWD_LOGIN", PACKET_HC_SECOND_PASSWD_LOGIN.self) { p, c in
            c.expect(p.packetType, HEADER_HC_SECOND_PASSWD_LOGIN, "packetType")
            c.expect(p.seed, 0xcafebabe, "seed")
            c.expect(p.AID, 2000001, "AID")
            c.expect(p.result, 1, "result")
        }

        problems += checkServerPacket("ZC_ACCEPT_ENTER", PACKET_ZC_ACCEPT_ENTER.self) { p, c in
            c.expect(p.packetType, HEADER_ZC_ACCEPT_ENTER, "packetType")
            c.expect(p.startTime, 123456, "startTime")
            // x=150, y=200, dir=3 packed by WBUFPOS
            c.expect(p.posDir, [0x25, 0x8c, 0x83], "posDir")
            c.expect(p.xSize, 5, "xSize")
            c.expect(p.ySize, 5, "ySize")
            c.expect(p.font, 2, "font")
        }

        problems += checkServerPacket("ZC_NOTIFY_PLAYERMOVE", PACKET_ZC_NOTIFY_PLAYERMOVE.self) { p, c in
            c.expect(p.packetType, HEADER_ZC_NOTIFY_PLAYERMOVE, "packetType")
            c.expect(p.moveStartTime, 123456, "moveStartTime")
            // (150,200) -> (153,203), sx0=8, sy0=8 packed by WBUFPOS2
            c.expect(p.moveData, [0x25, 0x8c, 0x82, 0x64, 0xcb, 0x88], "moveData")
        }

        problems += checkServerPacket("ZC_NOTIFY_TIME", PACKET_ZC_NOTIFY_TIME.self) { p, c in
            c.expect(p.packetType, HEADER_ZC_NOTIFY_TIME, "packetType")
            c.expect(p.time, 654321, "time")
        }

        // rAthena zero terminates the message, the client encodes it without the terminator, so no round trip.
        problems += checkServerPacket("ZC_NOTIFY_PLAYERCHAT", PACKET_ZC_NOTIFY_PLAYERCHAT.self, roundTrip: false) { p, c in
            c.expect(p.packetType, 0x8e, "packetType")
            c.expect(Int(p.packetLength), 26, "packetLength")
            c.expect(p.Message, "Alice : Hello, world!", "Message")
        }

        problems += checkServerPacket("ZC_NOTIFY_CHAT", PACKET_ZC_NOTIFY_CHAT.self, roundTrip: false) { p, c in
            c.expect(p.packetType, HEADER_ZC_NOTIFY_CHAT, "packetType")
            c.expect(Int(p.packetLength), 14, "packetLength")
            c.expect(p.GID, 150000, "GID")
            c.expect(p.Message, "Hello", "Message")
        }

        report("golden-s2c", problems)
    }

    // MARK: - Golden packets, client to server

    /// Checks that the client's table gives `data`'s opcode the length and parse function rAthena registers for it.
    private func checkClientPacketFraming(_ name: String, _ data: Data, function: String?, _ check: GoldenChecker) {
        let op = Int(data[data.startIndex]) | Int(data[data.startIndex + 1]) << 8
        // Packets only the login and char server read are not in rAthena's table.
        guard let entry = G.packets.first(where: { $0.opcode == op }) else {
            if !G.headerValues.values.contains(op) {
                check.fail("framing", "\(name) (\(hex4(op))) is neither in rAthena's packet table nor a HEADER_* constant")
            }
            return
        }
        check.expect(entry.function ?? "none", function ?? "none", "rAthena parse function")
        if entry.length != -1 {
            check.expect(data.count, entry.length, "rAthena table length")
        }
    }

    private func checkClientPacket(_ name: String, function: String?, _ packet: some EncodablePacket) -> [GoldenProblem] {
        let check = GoldenChecker("golden-c2s", name)
        let expected = goldenData(name)
        checkClientPacketFraming(name, expected, function: function, check)
        do {
            let encoded = try encode(packet)
            if encoded != expected {
                check.fail("bytes", "client encodes \(hexString(encoded)), rAthena expects \(hexString(expected))")
            }
        } catch {
            check.fail("encode", "encoding failed: \(error)")
        }
        return check.problems
    }

    func testClientToServerGoldenPackets() {
        var problems: [GoldenProblem] = []

        // Values as PacketFactory.CA_LOGIN sets them, except version and clienttype which the factory leaves 0.
        var caLogin = PACKET_CA_LOGIN()
        caLogin.packetType = HEADER_CA_LOGIN
        caLogin.version = 20211103
        caLogin.username = "ratest"
        caLogin.password = "secret"
        caLogin.clienttype = 22
        problems += checkClientPacket("CA_LOGIN", function: nil, caLogin)

        // PacketFactory.CH_ENTER
        var chEnter = PACKET_CH_ENTER()
        chEnter.packetType = HEADER_CH_ENTER
        chEnter.accountID = 2000001
        chEnter.loginID1 = 0x11223344
        chEnter.loginID2 = 0x55667788
        chEnter.clientType = 22
        chEnter.sex = 1
        problems += checkClientPacket("CH_ENTER", function: nil, chEnter)

        // PacketFactory has no CH_SECOND_PASSWD_ACK builder, use the generated struct directly.
        var secondPassword = PACKET_CH_SECOND_PASSWD_ACK()
        secondPassword.packetType = HEADER_CH_SECOND_PASSWD_ACK
        secondPassword.AID = 2000001
        secondPassword.pin = "1234"
        problems += checkClientPacket("CH_SECOND_PASSWD_ACK", function: nil, secondPassword)

        // PacketFactory.CZ_ENTER
        var czEnter = PACKET_CZ_ENTER()
        czEnter.accountID = 2000001
        czEnter.charID = 150000
        czEnter.loginID1 = 0x11223344
        czEnter.clientTime = 123456
        czEnter.sex = 1
        problems += checkClientPacket("CZ_ENTER", function: "clif_parse_WantToConnection", czEnter)

        // PacketFactory.CZ_REQUEST_MOVE(position: (300, 500))
        var czRequestMove = PACKET_CZ_REQUEST_MOVE()
        czRequestMove.x = 300
        czRequestMove.y = 500
        problems += checkClientPacket("CZ_REQUEST_MOVE", function: "clif_parse_WalkToXY", czRequestMove)

        // PacketFactory.CZ_REQUEST_CHAT(message:), the message includes the "<name> : " prefix the server checks.
        var czRequestChat = PACKET_CZ_REQUEST_CHAT()
        czRequestChat.message = "Alice : Hello, world!"
        problems += checkClientPacket("CZ_REQUEST_CHAT", function: "clif_parse_GlobalMessage", czRequestChat)

        // PacketFactory.CZ_REQUEST_TIME(clientTime:)
        var czRequestTime = PACKET_CZ_REQUEST_TIME()
        czRequestTime.clientTime = 123456
        problems += checkClientPacket("CZ_REQUEST_TIME", function: "clif_parse_TickSend", czRequestTime)

        report("golden-c2s", problems)
    }
}
