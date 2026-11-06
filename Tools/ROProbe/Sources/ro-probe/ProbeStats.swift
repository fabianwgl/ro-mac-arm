import Foundation

/// Everything the probe counts. Written from the proxy threads and the main actor, so it is lock protected.
final class ProbeStats: @unchecked Sendable {
    struct ReceivedOpcode {
        var opcode: Int
        var name: String?
        var decoded = 0
        var unimplemented = 0
        var unknown = 0
        var decodeFailures = 0
        var lengthMismatches = 0
        var bytes = 0
        var firstError: String?
        var roles: Set<String> = []
    }

    struct SentOpcode {
        var opcode: Int
        var name: String?
        var count = 0
        var bytes = 0
    }

    struct Event {
        var time: Double
        var message: String
    }

    private let lock = NSLock()
    let startDate = Date()
    private(set) var endDate: Date?

    private var received: [Int: ReceivedOpcode] = [:]
    private var sent: [Int: SentOpcode] = [:]

    private(set) var disconnects = 0
    private(set) var reconnects = 0
    private(set) var errors: [Event] = []
    private(set) var stages: [Event] = []
    private(set) var disconnectEvents: [Event] = []
    private(set) var notes: [Event] = []
    private(set) var lastStage = "notStarted"

    private(set) var deaths = 0
    private(set) var mapsVisited: [String] = []
    private(set) var chatLinesSent = 0
    private(set) var walkRequestsSent = 0
    private(set) var attacksSent = 0
    private(set) var monstersSeen: Set<UInt32> = []
    private(set) var streamDesyncs = 0
    private(set) var clientBugEvents = 0
    private(set) var connections: [String: Int] = [:]
    private(set) var sessions: [[String: Any]] = []
    private(set) var tapEnabled = true

    private(set) var characterCreated: String?
    private(set) var deleteTest: [String: Any]?
    private(set) var reachedMap = false
    private(set) var timeOnMap: Double = 0
    private(set) var mapName: String?
    private(set) var playerPositions: [String] = []

    var elapsed: Double {
        Date().timeIntervalSince(startDate)
    }

    // MARK: - Packets

    func recordReceived(opcode: Int, name: String?, kind: String, bytes: Int, role: String, lengthMismatch: Bool = false, error: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        var entry = received[opcode] ?? ReceivedOpcode(opcode: opcode)
        if entry.name == nil {
            entry.name = name
        }
        switch kind {
        case "decoded": entry.decoded += 1
        case "unimplemented": entry.unimplemented += 1
        case "unknown": entry.unknown += 1
        case "decodeFailure": entry.decodeFailures += 1
        default: break
        }
        if lengthMismatch {
            entry.lengthMismatches += 1
        }
        entry.bytes += bytes
        entry.roles.insert(role)
        if entry.firstError == nil, let error {
            entry.firstError = error
        }
        received[opcode] = entry
    }

    func recordSent(opcode: Int, name: String?, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }

        var entry = sent[opcode] ?? SentOpcode(opcode: opcode)
        if entry.name == nil {
            entry.name = name
        }
        entry.count += 1
        entry.bytes += bytes
        sent[opcode] = entry
    }

    func sentCount(opcode: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sent[opcode]?.count ?? 0
    }

    func recordMonster(id: UInt32) {
        lock.lock()
        monstersSeen.insert(id)
        lock.unlock()
    }

    func recordDesync() {
        lock.lock()
        streamDesyncs += 1
        lock.unlock()
    }

    func recordConnection(role: String) {
        lock.lock()
        connections[role, default: 0] += 1
        lock.unlock()
    }

    // MARK: - Events

    func recordStage(_ stage: String) {
        lock.lock()
        defer { lock.unlock() }
        if lastStage != stage {
            lastStage = stage
            stages.append(Event(time: elapsed, message: stage))
        }
    }

    func recordError(_ message: String) {
        lock.lock()
        errors.append(Event(time: elapsed, message: message))
        lock.unlock()
        Log.line("ERROR \(message)")
    }

    func recordDisconnect(_ message: String) {
        lock.lock()
        disconnects += 1
        disconnectEvents.append(Event(time: elapsed, message: message))
        lock.unlock()
        Log.line("DISCONNECT \(message)")
    }

    func recordReconnect() {
        lock.lock()
        reconnects += 1
        lock.unlock()
    }

    func recordClientBug(_ message: String) {
        lock.lock()
        clientBugEvents += 1
        let first = clientBugEvents == 1
        lock.unlock()
        if first {
            recordNote("client bug: \(message)")
        }
        Log.line("CLIENT BUG \(message)")
    }

    func recordNote(_ message: String) {
        lock.lock()
        notes.append(Event(time: elapsed, message: message))
        lock.unlock()
    }

    func addDeath() { lock.lock(); deaths += 1; lock.unlock() }
    func addChat() { lock.lock(); chatLinesSent += 1; lock.unlock() }
    func addWalk() { lock.lock(); walkRequestsSent += 1; lock.unlock() }
    func addAttack() { lock.lock(); attacksSent += 1; lock.unlock() }

    func setTapEnabled(_ enabled: Bool) {
        lock.lock()
        tapEnabled = enabled
        lock.unlock()
    }

    func setCharacterCreated(_ name: String) {
        lock.lock()
        characterCreated = name
        lock.unlock()
    }

    func setDeleteTest(_ result: [String: Any]) {
        lock.lock()
        deleteTest = result
        lock.unlock()
    }

    func setReachedMap(mapName: String) {
        lock.lock()
        reachedMap = true
        self.mapName = mapName
        if mapsVisited.last != mapName {
            mapsVisited.append(mapName)
        }
        lock.unlock()
    }

    func addTimeOnMap(_ seconds: Double) {
        lock.lock()
        timeOnMap += seconds
        lock.unlock()
    }

    func recordSession(_ session: [String: Any]) {
        lock.lock()
        sessions.append(session)
        lock.unlock()
    }

    func recordPosition(_ text: String) {
        lock.lock()
        if playerPositions.count < 50 {
            playerPositions.append(text)
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        endDate = Date()
        lock.unlock()
    }

    // MARK: - Output

    private func hex(_ opcode: Int) -> String {
        "0x" + String(format: "%04x", opcode)
    }

    private func eventJSON(_ events: [Event]) -> [[String: Any]] {
        events.map { ["t": (($0.time * 10).rounded() / 10), "message": $0.message] }
    }

    func summary(options: Options) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        let end = endDate ?? Date()

        var receivedRows: [[String: Any]] = []
        var unknown: [[String: Any]] = []
        var unimplemented: [[String: Any]] = []
        var decodeFailures: [[String: Any]] = []
        var mismatches: [[String: Any]] = []
        var totals = ["decoded": 0, "unimplemented": 0, "unknown": 0, "decodeFailures": 0, "bytes": 0]

        for entry in received.values.sorted(by: { $0.opcode < $1.opcode }) {
            var row: [String: Any] = [
                "opcode": hex(entry.opcode),
                "decoded": entry.decoded,
                "unimplemented": entry.unimplemented,
                "unknown": entry.unknown,
                "decodeFailures": entry.decodeFailures,
                "bytes": entry.bytes,
                "roles": entry.roles.sorted(),
            ]
            if let name = entry.name {
                row["name"] = name
            }
            receivedRows.append(row)

            totals["decoded", default: 0] += entry.decoded
            totals["unimplemented", default: 0] += entry.unimplemented
            totals["unknown", default: 0] += entry.unknown
            totals["decodeFailures", default: 0] += entry.decodeFailures
            totals["bytes", default: 0] += entry.bytes

            if entry.unknown > 0 {
                unknown.append(["opcode": hex(entry.opcode), "count": entry.unknown, "roles": entry.roles.sorted()])
            }
            if entry.unimplemented > 0 {
                var item: [String: Any] = ["opcode": hex(entry.opcode), "count": entry.unimplemented, "roles": entry.roles.sorted()]
                if let name = entry.name {
                    item["name"] = name
                }
                unimplemented.append(item)
            }
            if entry.decodeFailures > 0 {
                var item: [String: Any] = ["opcode": hex(entry.opcode), "count": entry.decodeFailures]
                if let name = entry.name {
                    item["name"] = name
                }
                if let firstError = entry.firstError {
                    item["firstError"] = firstError
                }
                decodeFailures.append(item)
            }
            if entry.lengthMismatches > 0 {
                var item: [String: Any] = ["opcode": hex(entry.opcode), "count": entry.lengthMismatches]
                if let name = entry.name {
                    item["name"] = name
                }
                mismatches.append(item)
            }
        }

        var sentRows: [[String: Any]] = []
        for entry in sent.values.sorted(by: { $0.opcode < $1.opcode }) {
            var row: [String: Any] = ["opcode": hex(entry.opcode), "count": entry.count, "bytes": entry.bytes]
            if let name = entry.name {
                row["name"] = name
            }
            sentRows.append(row)
        }

        var result: [String: Any] = [
            "startedAt": ISO8601DateFormatter().string(from: startDate),
            "endedAt": ISO8601DateFormatter().string(from: end),
            "durationSeconds": ((end.timeIntervalSince(startDate)) * 10).rounded() / 10,
            "requestedDurationSeconds": options.duration,
            "timeOnMapSeconds": (timeOnMap * 10).rounded() / 10,
            "options": [
                "host": options.host,
                "port": Int(options.port),
                "user": options.user,
                "charName": options.charName,
                "chatInterval": options.chatInterval,
                "walkInterval": options.walkInterval,
                "attackInterval": options.attackInterval,
                "reconnect": options.reconnect,
                "deleteTest": options.deleteTest,
                "tap": tapEnabled,
            ] as [String: Any],
            "tapEnabled": tapEnabled,
            "lastStage": lastStage,
            "reachedMap": reachedMap,
            "disconnects": disconnects,
            "reconnects": reconnects,
            "errorCount": errors.count,
            "errors": eventJSON(errors),
            "disconnectEvents": eventJSON(disconnectEvents),
            "stageHistory": eventJSON(stages),
            "notes": eventJSON(notes),
            "chatLinesSent": chatLinesSent,
            "walkRequestsSent": walkRequestsSent,
            "attacksSent": attacksSent,
            "deaths": deaths,
            "mapsVisited": mapsVisited,
            "monstersSeen": monstersSeen.count,
            "streamDesyncs": streamDesyncs,
            "connectPacketCoalesced": clientBugEvents,
            "connectionsAccepted": connections,
            "sessions": sessions,
            "packetTotals": totals,
            "packetsReceivedByOpcode": receivedRows,
            "unknownPackets": unknown,
            "unimplementedPackets": unimplemented,
            "decodeFailures": decodeFailures,
            "registeredSizeVsWireLengthMismatches": mismatches,
            "packetsSentByOpcode": sentRows,
            "samplePositions": playerPositions,
        ]
        if let mapName {
            result["mapName"] = mapName
        }
        if let characterCreated {
            result["characterCreated"] = characterCreated
        }
        if let deleteTest {
            result["deleteTest"] = deleteTest
        }
        return result
    }

    func writeJSON(options: Options) {
        guard let path = options.jsonPath else {
            return
        }
        let summary = summary(options: options)
        do {
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            Log.line("wrote summary to \(path)")
        } catch {
            Log.line("failed to write summary: \(error)")
        }
    }

    func printSummary(options: Options) {
        let summary = summary(options: options)
        func int(_ key: String) -> Int { (summary[key] as? Int) ?? 0 }
        let totals = summary["packetTotals"] as? [String: Int] ?? [:]
        var lines: [String] = []
        lines.append("")
        lines.append("==== ro-probe summary ====")
        lines.append("duration            \(summary["durationSeconds"] ?? 0) s (on map \(summary["timeOnMapSeconds"] ?? 0) s, requested \(options.duration) s)")
        lines.append("last stage          \(lastStage)")
        lines.append("reached map         \(reachedMap)\(mapName.map { " (\($0))" } ?? "")")
        lines.append("disconnects         \(disconnects)")
        lines.append("reconnects          \(reconnects)")
        lines.append("errors              \(errors.count)")
        lines.append("chat lines sent     \(chatLinesSent)")
        lines.append("walk requests sent  \(walkRequestsSent)")
        lines.append("attacks sent        \(attacksSent)")
        lines.append("monsters seen       \(monstersSeen.count)")
        lines.append("deaths              \(deaths)")
        lines.append("maps visited        \(mapsVisited.joined(separator: " > "))")
        lines.append("connect coalesced   \(clientBugEvents) (map CZ_ENTER shared a TCP read with a later packet)")
        if tapEnabled {
            lines.append("packets received    decoded \(totals["decoded"] ?? 0), unimplemented \(totals["unimplemented"] ?? 0), unknown \(totals["unknown"] ?? 0), decode failures \(totals["decodeFailures"] ?? 0), bytes \(totals["bytes"] ?? 0)")
            lines.append("distinct opcodes    \(received.count) received, \(sent.count) sent")
        } else {
            lines.append("packets received    (tap disabled)")
        }
        _ = int("errorCount")
        for item in (summary["unknownPackets"] as? [[String: Any]]) ?? [] {
            lines.append("  UNKNOWN       \(item["opcode"] ?? "") x\(item["count"] ?? 0)")
        }
        for item in (summary["unimplementedPackets"] as? [[String: Any]]) ?? [] {
            lines.append("  UNIMPLEMENTED \(item["opcode"] ?? "") x\(item["count"] ?? 0) \(item["name"] ?? "")")
        }
        for item in (summary["decodeFailures"] as? [[String: Any]]) ?? [] {
            lines.append("  DECODE FAILED \(item["opcode"] ?? "") x\(item["count"] ?? 0) \(item["name"] ?? "") \(item["firstError"] ?? "")")
        }
        for item in (summary["registeredSizeVsWireLengthMismatches"] as? [[String: Any]]) ?? [] {
            lines.append("  SIZE MISMATCH \(item["opcode"] ?? "") x\(item["count"] ?? 0) \(item["name"] ?? "")")
        }
        for event in errors.prefix(20) {
            lines.append("  error @\(String(format: "%.1f", event.time))s: \(event.message)")
        }
        lines.append("")
        print(lines.joined(separator: "\n"))
        fflush(stdout)
    }
}
