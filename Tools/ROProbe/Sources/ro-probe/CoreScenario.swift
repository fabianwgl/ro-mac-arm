import AVFAudio
import Foundation
import RagnarokConstants
import RagnarokCore
@testable import RagnarokGame
import RagnarokModels
import RagnarokPackets
import RagnarokResources
import simd

/// The `--scenario core` checks for plan tasks P3-02 and P3-05..P3-13.
///
/// Every check goes through the entry points the UI uses (`PlaySession` methods, `MapScene.handleInteraction`,
/// `MapScene.useSkill` via `PlaySession.useShortcut`), then waits for the server's answer packet and for the
/// client state that packet should change. Chat GM commands (`@item`, `@blvl`, `@jobchange` ..) are only used to
/// set up a situation, or where the check is about the GM path itself (`@warp`).
@MainActor
final class CoreScenario {
    // MARK: - Report types

    struct Check {
        var name: String
        var passed: Bool
        var detail: String
    }

    struct TaskReport {
        var id: String
        var title: String
        var summary = ""
        var checks: [Check] = []
        var notes: [String] = []
        var seconds = 0.0
        var packetsReceived: [String: Int] = [:]
        var packetsSent: [String: Int] = [:]
        var skipped = false
        /// Chat and system lines the client received during the task (GM command answers, item and skill messages).
        var serverMessages: [String] = []

        var passed: Bool {
            !skipped && !checks.isEmpty && checks.allSatisfy(\.passed)
        }
    }

    // MARK: - State

    private let runner: ProbeRunner
    private let options: Options
    private let stats: ProbeStats
    private let gameSession: GameSession
    private let playSession: PlaySession

    private var report = TaskReport(id: "", title: "")
    private var reportStartIndex = 0
    private var reportStartDate = Date()
    private var reports: [TaskReport] = []
    private var lastRespawnRequest = Date.distantPast
    private var visitedMaps: [String] = []
    private var lastItemIDs: Set<GameObjectID> = []
    private var seenMessageIDs: Set<UUID> = []

    private var scene: MapScene? { playSession.mapScene }
    private var status: CharacterStatus { playSession.playerStatus }

    init(runner: ProbeRunner, gameSession: GameSession, playSession: PlaySession) {
        self.runner = runner
        self.options = runner.options
        self.stats = runner.stats
        self.gameSession = gameSession
        self.playSession = playSession
    }

    // MARK: - Entry

    func run() async -> Bool {
        stats.tracesPackets = options.tracePackets
        stats.setPacketLogging(true)
        let startDate = Date()

        let all: [(String, () async -> Void)] = [
            ("P3-07", { await self.p307() }),
            ("P3-05", { await self.p305() }),
            ("P3-06", { await self.p306() }),
            ("P3-10", { await self.p310() }),
            ("P3-11", { await self.p311() }),
            ("P3-08", { await self.p308() }),
            ("P3-09", { await self.p309() }),
            ("P3-02", { await self.p302() }),
            ("P3-13", { await self.p313() }),
        ]

        noteMap()
        // The inventory, skill and status lists arrive right after the map entry.
        await pause(3)
        for (id, body) in all {
            if !options.tasks.isEmpty, !options.tasks.contains(id) {
                continue
            }
            if runner.stopRequested || gameSession.isDisconnected || gameSession.playSession == nil {
                break
            }
            await body()
        }

        let passedIDs = reports.filter(\.passed).map(\.id)
        let failedIDs = reports.filter { !$0.passed && !$0.skipped }.map(\.id)
        let result: [String: Any] = [
            "name": "core",
            "character": playSession.character.name,
            "seconds": ((Date().timeIntervalSince(startDate)) * 10).rounded() / 10,
            "passed": passedIDs,
            "failed": failedIDs,
            "tasks": reports.map(Self.json),
        ]
        stats.setScenario(result)
        stats.setPacketLogging(false)

        Log.line("scenario core: passed \(passedIDs.joined(separator: ", ")); failed \(failedIDs.isEmpty ? "none" : failedIDs.joined(separator: ", "))")
        return failedIDs.isEmpty && !reports.isEmpty
    }

    private static func json(_ task: TaskReport) -> [String: Any] {
        [
            "id": task.id,
            "title": task.title,
            "result": task.skipped ? "skipped" : (task.passed ? "pass" : "fail"),
            "summary": task.summary,
            "seconds": (task.seconds * 10).rounded() / 10,
            "checks": task.checks.map { ["name": $0.name, "passed": $0.passed, "detail": $0.detail] as [String: Any] },
            "notes": task.notes,
            "packetsReceived": task.packetsReceived,
            "packetsSent": task.packetsSent,
            "serverMessages": task.serverMessages,
        ]
    }

    // MARK: - Report helpers

    private func begin(_ id: String, _ title: String) {
        report = TaskReport(id: id, title: title)
        reportStartIndex = stats.packetLogCount
        reportStartDate = Date()
        Log.line("==== \(id) \(title)")
    }

    private func end() {
        report.seconds = Date().timeIntervalSince(reportStartDate)
        for packet in stats.packets(since: reportStartIndex) {
            let name = Self.displayName(packet.name, opcode: packet.opcode)
            if packet.received {
                report.packetsReceived[name, default: 0] += 1
            } else {
                report.packetsSent[name, default: 0] += 1
            }
        }
        Log.line("---- \(report.id) \(report.passed ? "PASS" : "FAIL") (\(report.checks.filter(\.passed).count)/\(report.checks.count) checks)")
        reports.append(report)
        noteMap()
    }

    private func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        report.checks.append(Check(name: name, passed: passed, detail: detail))
        Log.line("  [\(passed ? "ok" : "FAIL")] \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    private func note(_ text: String) {
        report.notes.append(text)
        Log.line("  note: \(text)")
    }

    private func noteMap() {
        if let name = scene?.mapName, visitedMaps.last != name {
            visitedMaps.append(name)
            stats.setReachedMap(mapName: name)
        }
    }

    private static func displayName(_ name: String, opcode: Int) -> String {
        let first = name.components(separatedBy: " | ").first ?? name
        let stripped = first.replacingOccurrences(of: "PACKET_", with: "").replacingOccurrences(of: "HEADER_", with: "")
        let hex = "0x" + String(format: "%04x", opcode)
        return stripped.isEmpty ? hex : "\(stripped) (\(hex))"
    }

    // MARK: - Packet matching

    /// True when the packet name has an alias equal to `token`, ignoring the `PACKET_` and `HEADER_` prefixes.
    private static func matches(_ name: String, _ token: String) -> Bool {
        for alias in name.components(separatedBy: " | ") {
            let bare = alias
                .replacingOccurrences(of: "(not in packet database)", with: "")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "PACKET_", with: "")
                .replacingOccurrences(of: "HEADER_", with: "")
            if bare == token {
                return true
            }
        }
        return false
    }

    private func mark() -> Int {
        stats.packetLogCount
    }

    private func count(_ token: String, received: Bool = true, since index: Int) -> Int {
        stats.packets(since: index).filter { $0.received == received && Self.matches($0.name, token) }.count
    }

    private func received(_ token: String, since index: Int) -> Int {
        count(token, received: true, since: index)
    }

    private func sent(_ token: String, since index: Int) -> Int {
        sentPackets(token, since: index).count
    }

    private func sentPayloads(_ token: String, since index: Int) -> [[UInt8]] {
        sentPackets(token, since: index).map(\.payload)
    }

    private func sentPackets(_ token: String, since index: Int) -> [ProbeStats.LoggedPacket] {
        let function = SentFunctionNames.byPacket[token]
        return stats.packets(since: index).filter { packet in
            !packet.received && (Self.matches(packet.name, token) || function.map { Self.matches(packet.name, $0) } == true)
        }
    }

    // MARK: - Waiting

    /// Ticks the map runtime the way the app's render loop does, and keeps the character alive.
    private func tick() {
        if let runtime = playSession.mapRuntime {
            runtime.update(at: .now, renderTime: ProcessInfo.processInfo.systemUptime)
        }
        for message in playSession.messageCenter.messages where !seenMessageIDs.contains(message.id) {
            seenMessageIDs.insert(message.id)
            Log.line("server message: \(message.content)")
            if report.serverMessages.count < 40 {
                report.serverMessages.append(message.content)
            }
        }
        if let scene {
            let ids = Set(scene.items.keys)
            if ids != lastItemIDs {
                for id in ids.subtracting(lastItemIDs) {
                    Log.line("floor item appeared: \(id) item \(scene.items[id]?.itemID ?? 0) at \(scene.items[id]?.gridPosition ?? .zero)")
                }
                for id in lastItemIDs.subtracting(ids) {
                    Log.line("floor item gone: \(id)")
                }
                lastItemIDs = ids
            }
        }
        if playSession.playerStatus.hp <= 0, Date().timeIntervalSince(lastRespawnRequest) > 8 {
            lastRespawnRequest = Date()
            Log.line("player is dead, requesting respawn at the save point")
            stats.addDeath()
            playSession.returnToLastSavePoint()
        }
    }

    private var aborted: Bool {
        runner.stopRequested || gameSession.isDisconnected || gameSession.playSession == nil
    }

    /// Polls `condition` every 100 ms with the map runtime ticking. The condition may act (re-send a request).
    @discardableResult
    private func pump(_ timeout: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            tick()
            if condition() {
                return true
            }
            if aborted {
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        tick()
        return condition()
    }

    private func pause(_ seconds: TimeInterval) async {
        await pump(seconds) { false }
    }

    private func say(_ text: String) {
        Log.line("chat: \(text)")
        playSession.sendMessage(text)
        stats.addChat()
    }

    /// A GM command, then a short settle time for the server's answer.
    private func gm(_ command: String, settle: TimeInterval = 1.2) async {
        say(command)
        await pause(settle)
    }

    private func describeStatus() -> String {
        let s = status
        return "lv \(s.baseLevel) exp \(s.baseExp)/\(s.baseExpNext) hp \(s.hp)/\(s.maxHp) sp \(s.sp)/\(s.maxSp) zeny \(s.zeny) weight \(s.weight)/\(s.maxWeight) stp \(s.statusPoint) skp \(s.skillPoint)"
    }

    private func firstItem(_ itemID: Int, equipped: Bool? = nil) -> InventoryItem? {
        playSession.inventory.items.values
            .filter { $0.itemID == itemID && (equipped == nil || $0.isEquipped == equipped) }
            .sorted()
            .first
    }

    private func amount(of itemID: Int) -> Int {
        playSession.inventory.items.values.filter { $0.itemID == itemID }.reduce(0) { $0 + $1.amount }
    }

    private func monsters() -> [MapSceneMapObject] {
        guard let scene else { return [] }
        return scene.objects.values
            .filter { $0.type == .monster && !$0.isDead }
            .sorted { distance($0.gridPosition, scene.player.gridPosition) < distance($1.gridPosition, scene.player.gridPosition) }
    }

    private func distance(_ a: SIMD2<Int>, _ b: SIMD2<Int>) -> Int {
        max(abs(a.x - b.x), abs(a.y - b.y))
    }

    /// Makes sure at least one monster is in view, spawning Porings next to the character if needed.
    private func ensureMonster(spawn: Int = 2) async -> Bool {
        if !monsters().isEmpty {
            return true
        }
        say("@monster poring \(spawn)")
        return await pump(15) { !self.monsters().isEmpty }
    }

    /// Heals the character and waits until the HP and SP the client shows are full.
    private func heal() async {
        say("@heal 9999 9999")
        await pump(4) { self.status.hp > 0 && self.status.hp >= self.status.maxHp && self.status.sp >= self.status.maxSp }
    }

    /// Waits for a map change the server announced with `ZC_NPCACK_MAPMOVE`, until the map scene exists again and
    /// the client told the server it is ready (`CZ_NOTIFY_ACTORINIT`).
    private func awaitMapChange(since index: Int, timeout: TimeInterval = 90) async -> (map: String, position: SIMD2<Int>)? {
        let moved = await pump(timeout) { self.received("ZC_NPCACK_MAPMOVE", since: index) > 0 }
        guard moved else { return nil }
        let ready = await pump(timeout) {
            self.scene != nil && self.sent("CZ_NOTIFY_ACTORINIT", since: index) > 0
        }
        guard ready, let scene else { return nil }
        // Let the objects of the new map arrive.
        await pause(1.5)
        noteMap()
        return (scene.mapName, scene.player.gridPosition)
    }

    // MARK: - P3-07 Inventory, equipment, weight

    private func p307() async {
        begin("P3-07", "Inventory, equipment, and weight")
        await heal()

        let weight0 = status.weight
        let potions0 = amount(of: 501)
        let index0 = mark()

        // Items arrive through the server's pickup acknowledgement, as when an item is picked up.
        await gm("@item 501 10", settle: 0.5)
        let gotPotions = await pump(8) { self.amount(of: 501) >= potions0 + 10 }
        check("add consumables (@item 501 10)", gotPotions, "red potions \(potions0) -> \(amount(of: 501)); ZC_ITEM_PICKUP_ACK x\(received("ZC_ITEM_PICKUP_ACK", since: index0))")

        let weightUp = await pump(5) { self.status.weight >= weight0 + 700 }
        check("weight rises by the item weight (10 x 70)", weightUp, "weight \(weight0) -> \(status.weight) (max \(status.maxWeight)); ZC_PAR_CHANGE x\(received("ZC_PAR_CHANGE", since: index0))")
        check("max weight known", status.maxWeight > 0, "maxWeight \(status.maxWeight)")

        await gm("@item 1201 1", settle: 0.3)
        await gm("@item 2301 1", settle: 0.3)
        let gotGear = await pump(8) { self.firstItem(1201, equipped: false) != nil && self.firstItem(2301, equipped: false) != nil }
        check("add equipment (spare Knife 1201 and Cotton Shirt 2301)", gotGear, "knife \(firstItem(1201, equipped: false).map { "index \($0.index) location \($0.location.rawValue)" } ?? "missing"), shirt \(firstItem(2301, equipped: false).map { "index \($0.index) location \($0.location.rawValue)" } ?? "missing")")

        // Use an item: the potion count and the weight drop together.
        if let potion = firstItem(501) {
            let beforeAmount = potion.amount
            let beforeWeight = status.weight
            let useMark = mark()
            playSession.useItem(at: potion.index)
            let used = await pump(8) { (self.firstItem(501)?.amount ?? 0) == beforeAmount - 1 }
            check("use item (CZ_USE_ITEM then ZC_USE_ITEM_ACK)", used && received("ZC_USE_ITEM_ACK", since: useMark) > 0, "potions \(beforeAmount) -> \(firstItem(501)?.amount ?? 0); ZC_USE_ITEM_ACK x\(received("ZC_USE_ITEM_ACK", since: useMark))")
            let lighter = await pump(5) { self.status.weight == beforeWeight - 70 }
            check("weight falls by one potion (70)", lighter, "weight \(beforeWeight) -> \(status.weight)")
        } else {
            check("use item", false, "no red potion in the inventory")
        }

        // Equip and unequip through the same calls as the inventory list. A new character already wears a Knife and
        // a Cotton Shirt, so the spare knife swaps with the worn one, and the worn shirt comes off and goes back on.
        if let knife = firstItem(1201, equipped: false) {
            let equipMark = mark()
            playSession.equipItem(at: knife.index, location: knife.location)
            let equipped = await pump(8) { self.playSession.inventory.items[knife.index]?.isEquipped == true }
            check("equip weapon (CZ_REQ_WEAR_EQUIP then ZC_REQ_WEAR_EQUIP_ACK)", equipped && sent("CZ_REQ_WEAR_EQUIP", since: equipMark) > 0 && received("ZC_REQ_WEAR_EQUIP_ACK", since: equipMark) > 0, "spare knife index \(knife.index) equippedLocation \(playSession.inventory.items[knife.index]?.equippedLocation.rawValue ?? -1); worn knives \(playSession.inventory.items.values.filter { $0.itemID == 1201 && $0.isEquipped }.count); ack x\(received("ZC_REQ_WEAR_EQUIP_ACK", since: equipMark))")
        } else {
            check("equip weapon", false, "no spare knife")
        }
        var wornShirt = firstItem(2301, equipped: true)
        if wornShirt == nil, let spare = firstItem(2301, equipped: false) {
            // A rerun on a used character: put a shirt on first so there is one to take off.
            playSession.equipItem(at: spare.index, location: spare.location)
            _ = await pump(8) { self.playSession.inventory.items[spare.index]?.isEquipped == true }
            wornShirt = playSession.inventory.items[spare.index]
        }
        if let shirt = wornShirt {
            let takeoffMark = mark()
            playSession.unequipItem(at: shirt.index)
            let removed = await pump(8) { self.playSession.inventory.items[shirt.index]?.isEquipped == false && self.playSession.inventory.item(equippedAt: .armor) == nil }
            check("unequip armor (CZ_REQ_TAKEOFF_EQUIP then ZC_REQ_TAKEOFF_EQUIP_ACK)", removed && received("ZC_REQ_TAKEOFF_EQUIP_ACK", since: takeoffMark) > 0, "armor slot item \(playSession.inventory.item(equippedAt: .armor)?.itemID ?? 0); ack x\(received("ZC_REQ_TAKEOFF_EQUIP_ACK", since: takeoffMark))")

            let equipMark = mark()
            playSession.equipItem(at: shirt.index, location: shirt.location)
            let worn = await pump(8) { self.playSession.inventory.item(equippedAt: .armor)?.index == shirt.index }
            check("equip armor again", worn && received("ZC_REQ_WEAR_EQUIP_ACK", since: equipMark) > 0, "armor slot item \(playSession.inventory.item(equippedAt: .armor)?.itemID ?? 0); ack x\(received("ZC_REQ_WEAR_EQUIP_ACK", since: equipMark))")
        } else {
            check("unequip and equip armor", false, "no worn shirt")
        }
        note("the knife stays equipped for the later combat checks")
        report.summary = "@item adds potions, a Knife and a Cotton Shirt; weight, use, equip and unequip answered by the server"
        end()
    }

    // MARK: - P3-05 Experience, level up, stat points (and the kills P3-06 loots)

    private var lootSeen = false
    /// Packet log index where the kills of P3-05 began; the drops of those kills belong to P3-06.
    private var huntMark = 0

    /// Attacks `target` through `MapScene.attackMonster` until it is dead or gone. Returns true when it died.
    private func kill(_ target: MapSceneMapObject, timeout: TimeInterval = 90) async -> Bool {
        var lastAttack = Date.distantPast
        let id = target.objectID
        return await pump(timeout) {
            guard let scene = self.scene else { return false }
            if scene.objects[id] == nil || scene.objects[id]?.isDead == true {
                return true
            }
            if Date().timeIntervalSince(lastAttack) > 2.5 {
                lastAttack = Date()
                scene.attackMonster(targetID: id)
                self.stats.addAttack()
            }
            if self.status.hp > 0, self.status.hp < self.status.maxHp / 3 {
                // Do not die to a Poring: heal as a player would with a potion.
                self.say("@heal 9999 9999")
            }
            return false
        }
    }

    private func p305() async {
        begin("P3-05", "Experience, level up, and stat points")
        await heal()

        let level0 = status.baseLevel
        let exp0 = status.baseExp
        let statusPointsStart = status.statusPoint
        let startMark = mark()
        huntMark = startMark
        Log.line("start \(describeStatus())")

        var kills = 0
        var expGained = false
        var attempts = 0
        // Kill until the experience bar fills (a level up from kills) and a drop lies on the ground for P3-06, at most 8 monsters.
        while attempts < 8, !aborted {
            attempts += 1
            guard await ensureMonster(spawn: 1) else {
                note("no monster appeared after @monster")
                break
            }
            guard let target = monsters().first else { continue }
            Log.line("attack \(target.name) \(target.objectID) at \(target.gridPosition)")
            let died = await kill(target)
            if died {
                kills += 1
            }
            await pause(1.0)
            if (status.baseExp != exp0 || status.baseLevel > level0) {
                expGained = true
            }
            if let scene, !scene.items.isEmpty {
                lootSeen = true
            }
            if status.baseLevel > level0, lootSeen {
                break
            }
        }

        check("kill a monster with the attack path", kills > 0, "\(kills) kill(s); CZ_REQUEST_ACT x\(sent("CZ_REQUEST_ACT", since: startMark))")
        let expPackets = received("ZC_NOTIFY_EXP", since: startMark)
        let naturalLevelUp = status.baseLevel > level0
        check("experience from the kill (ZC_NOTIFY_EXP, base exp changes)", expGained && expPackets > 0, "base exp \(exp0) -> \(status.baseExp)/\(status.baseExpNext), level \(level0) -> \(status.baseLevel); ZC_NOTIFY_EXP x\(expPackets)")

        // A level up: the kills may have done it. If not, ask the server for one level.
        if naturalLevelUp {
            note("level up came from kill experience")
        } else {
            await gm("@blvl 1", settle: 0.5)
            _ = await pump(8) { self.status.baseLevel > level0 }
            note("kills did not fill the experience bar (base exp \(status.baseExp)/\(status.baseExpNext)), level up by @blvl 1")
        }
        let leveled = status.baseLevel > level0
        let pointsUp = await pump(5) { self.status.statusPoint > statusPointsStart }
        check("level up (base level updates)", leveled, "level \(level0) -> \(status.baseLevel); natural \(naturalLevelUp)")
        check("level up grants status points", pointsUp, "status points \(statusPointsStart) -> \(status.statusPoint)")

        // Spend a stat point through the status window call.
        let before = status
        let spendMark = mark()
        playSession.incrementStatusProperty(.str, by: 1)
        let spent = await pump(8) { self.status.str == before.str + 1 }
        let usedPoints = before.statusPoint - status.statusPoint
        check("spend a stat point (CZ_STATUS_CHANGE then ZC_STATUS_CHANGE_ACK)", spent && usedPoints > 0 && received("ZC_STATUS_CHANGE_ACK", since: spendMark) > 0, "STR \(before.str) -> \(status.str), status points \(before.statusPoint) -> \(status.statusPoint) (cost \(usedPoints)); ack x\(received("ZC_STATUS_CHANGE_ACK", since: spendMark)), ZC_COUPLESTATUS x\(received("ZC_COUPLESTATUS", since: spendMark))")
        check("derived stats refreshed after the point", status.atk > 0 || status.hit > 0, "atk \(status.atk)+\(status.atk2) hit \(status.hit) flee \(status.flee)")
        report.summary = "\(kills) Poring kill(s) with the knife; exp and level up from the server; one STR point spent"
        end()
    }

    // MARK: - P3-06 Loot

    private func p306() async {
        begin("P3-06", "Loot, drops, and item pickup")
        let startMark = huntMark

        // A drop from the kills of P3-05 if one still lies there.
        if let scene, scene.items.isEmpty, !lootSeen {
            // Nothing dropped so far: kill more.
            for _ in 0..<6 where scene.items.isEmpty && !aborted {
                guard await ensureMonster(spawn: 1), let target = monsters().first else { break }
                _ = await kill(target)
                await pause(1.0)
            }
        }
        if let scene, let drop = scene.items.values.first {
            let itemID = drop.itemID
            let before = amount(of: itemID)
            let pickMark = mark()
            Log.line("pick up monster drop \(itemID) at \(drop.gridPosition)")
            scene.handleInteraction(.mapItem(objectID: drop.objectID))
            let picked = await pump(30) { self.amount(of: itemID) > before }
            let vanished = await pump(5) { self.scene?.items[drop.objectID] == nil }
            check("monster drop appeared on the ground (ZC_ITEM_FALL_ENTRY)", received("packet_dropflooritem", since: startMark) + received("ZC_ITEM_ENTRY", since: startMark) > 0, "item \(itemID); packet_dropflooritem x\(received("packet_dropflooritem", since: startMark))")
            check("pick up the drop by tapping it (walk, then CZ_ITEM_PICKUP and ZC_ITEM_PICKUP_ACK)", picked && received("ZC_ITEM_PICKUP_ACK", since: pickMark) > 0 && sent("CZ_ITEM_PICKUP", since: pickMark) > 0, "item \(itemID) amount \(before) -> \(amount(of: itemID)); CZ_ITEM_PICKUP x\(sent("CZ_ITEM_PICKUP", since: pickMark))")
            check("floor item removed after pickup (ZC_ITEM_DISAPPEAR)", vanished, "ZC_ITEM_DISAPPEAR x\(received("ZC_ITEM_DISAPPEAR", since: pickMark))")
        } else {
            check("monster drop appeared on the ground", false, "no drop after the kills")
        }

        // The player's own drop and pick up again.
        if let potion = firstItem(501), let scene {
            let before = potion.amount
            let weight0 = status.weight
            let throwMark = mark()
            playSession.throwItem(at: potion.index, amount: 2)
            let dropped = await pump(8) { (self.firstItem(501)?.amount ?? 0) == before - 2 && !(self.scene?.items.isEmpty ?? true) }
            check("throw items on the ground (CZ_ITEM_THROW, ZC_ITEM_THROW_ACK, floor item)", dropped && sent("CZ_ITEM_THROW", since: throwMark) > 0 && received("ZC_ITEM_THROW_ACK", since: throwMark) > 0, "potions \(before) -> \(firstItem(501)?.amount ?? 0); floor items \(self.scene?.items.count ?? 0); weight \(weight0) -> \(status.weight); ZC_ITEM_THROW_ACK x\(received("ZC_ITEM_THROW_ACK", since: throwMark))")
            if let floor = scene.items.values.first(where: { $0.itemID == 501 }) {
                // Walk a few cells away first, so the tap on the item has to walk back and pick up on arrival.
                let origin = scene.player.gridPosition
                var candidates: [SIMD2<Int>] = []
                for dx in -7...7 {
                    for dy in -7...7 {
                        let cell = SIMD2(floor.gridPosition.x + dx, floor.gridPosition.y + dy)
                        if distance(cell, floor.gridPosition) >= 4, scene.mapGrid.contains(cell), scene.mapGrid[cell].isWalkable,
                           scene.pathFinder.canRequestMove(from: origin, to: cell) {
                            candidates.append(cell)
                        }
                    }
                }
                if let away = candidates.randomElement() {
                    scene.handleInteraction(.ground(position: away))
                    let there = await pump(20) { self.scene?.player.gridPosition == away }
                    note("walked away from the thrown items to \(away.x),\(away.y): \(there ? "arrived" : "did not arrive")")
                }
                let pickMark = mark()
                let distanceBefore = distance(scene.player.gridPosition, floor.gridPosition)
                scene.handleInteraction(.mapItem(objectID: floor.objectID))
                let back = await pump(30) { (self.firstItem(501)?.amount ?? 0) >= before }
                let distanceAfter = distance(self.scene?.player.gridPosition ?? .zero, floor.gridPosition)
                check("tap the thrown items from \(distanceBefore) cells away: walk there, then pick up (CZ_REQUEST_MOVE, CZ_ITEM_PICKUP)", back && sent("CZ_ITEM_PICKUP", since: pickMark) > 0 && (distanceBefore <= 1 || sent("CZ_REQUEST_MOVE", since: pickMark) > 0), "potions \(firstItem(501)?.amount ?? 0); walked from \(distanceBefore) to \(distanceAfter) cell(s) of the items; CZ_REQUEST_MOVE x\(sent("CZ_REQUEST_MOVE", since: pickMark)), CZ_ITEM_PICKUP x\(sent("CZ_ITEM_PICKUP", since: pickMark))")
            } else {
                check("pick the thrown items up again", false, "no floor item for the thrown potions")
            }
        } else {
            check("throw items on the ground", false, "no potion")
        }
        report.summary = "monster drop picked up by tapping it; thrown potions dropped and picked up"
        end()
    }

    // MARK: - P3-10 Skill window, skill use, cooldowns

    private func learn(_ skillID: Int, levels: Int, label: String) async -> Bool {
        var ok = true
        for step in stride(from: 1, through: levels, by: 1) {
            let before = playSession.skillList.skills[skillID]?.level ?? 0
            let points = status.skillPoint
            let upMark = mark()
            playSession.upgradeSkillLevel(skillID: skillID)
            let up = await pump(6) { (self.playSession.skillList.skills[skillID]?.level ?? 0) > before }
            if !up {
                ok = false
                note("\(label) level \(before) did not go up (step \(step)/\(levels)), skill points \(points) -> \(status.skillPoint), ZC_SKILLINFO_UPDATE x\(received("ZC_SKILLINFO_UPDATE", since: upMark) + received("ZC_SKILLINFO_UPDATE2", since: upMark))")
                break
            }
        }
        return ok
    }

    private func p310() async {
        begin("P3-10", "Skill window, skill use, cooldowns")

        // Novice: Basic Skill to level 9. The server (player_skillup_limit) offers first-job skills only after that,
        // and the Kafra storage service wants level 6.
        let basicBefore = playSession.skillList.skills[1]?.level ?? 0
        let needed = max(9 - basicBefore, 0)
        if needed > 0 {
            await gm("@skillpoint \(needed)", settle: 0.4)
            let gotPoints = await pump(6) { self.status.skillPoint >= needed }
            check("skill points arrive (@skillpoint \(needed))", gotPoints, "skill points \(status.skillPoint)")
        }
        let skillMark = mark()
        let basicOK = await learn(1, levels: needed, label: "Basic Skill")
        let basicLevel = playSession.skillList.skills[1]?.level ?? 0
        check("learn Basic Skill to level 9 (CZ_UPGRADE_SKILLLEVEL, ZC_SKILLINFO_UPDATE)", basicOK && basicLevel >= 9, "level \(basicBefore) -> \(basicLevel); skill points \(status.skillPoint); update packets \(received("ZC_SKILLINFO_UPDATE", since: skillMark) + received("ZC_SKILLINFO_UPDATE2", since: skillMark))")

        // First job: Swordman. The skill list is replaced by the new job's.
        await gm("@jobchange 1", settle: 0.5)
        let hasBash = await pump(10) { self.playSession.skillList.skills[5] != nil }
        check("job change refreshes the skill list (@jobchange 1 = Swordman, ZC_SKILLINFO_LIST)", hasBash, "skills \(playSession.skillList.skills.keys.sorted())")
        if status.maxSp < 60 {
            await gm("@blvl 29", settle: 1.0)
        }
        let pointsBefore = status.skillPoint
        await gm("@skillpoint 6", settle: 0.4)
        _ = await pump(6) { self.status.skillPoint >= pointsBefore + 6 }

        let bashOK = await learn(5, levels: 5, label: "Bash")
        let magnumOK = await learn(7, levels: 1, label: "Magnum Break")
        let bash = playSession.skillList.skills[5]
        check("learn Bash 5 and Magnum Break 1 from the skill list", bashOK && magnumOK && (bash?.level ?? 0) == 5 && (playSession.skillList.skills[7]?.level ?? 0) == 1, "Bash \(bash?.level ?? 0) (sp \(bash?.spCost ?? 0)), Magnum Break \(playSession.skillList.skills[7]?.level ?? 0); skill points left \(status.skillPoint)")

        // Use a target skill on a monster through the shortcut call the skill list uses.
        await heal()
        if await ensureMonster(spawn: 2), let target = monsters().first {
            let sp0 = status.sp
            let useMark = mark()
            Log.line("Bash on \(target.name) \(target.objectID)")
            playSession.useShortcut(.skill(skillID: 5, level: 5))
            let sentOK = await pump(30) { self.sent("CZ_USE_SKILL", since: useMark) > 0 }
            let answered = await pump(10) {
                self.received("ZC_NOTIFY_SKILL", since: useMark) + self.received("ZC_USE_SKILL", since: useMark) + self.received("ZC_NOTIFY_ACT", since: useMark) > 0
            }
            check("use Bash on a monster (CZ_USE_SKILL, damage packet)", sentOK && answered, "CZ_USE_SKILL x\(sent("CZ_USE_SKILL", since: useMark)); ZC_USE_SKILL x\(received("ZC_USE_SKILL", since: useMark)) ZC_NOTIFY_SKILL x\(received("ZC_NOTIFY_SKILL", since: useMark)); sp \(sp0) -> \(status.sp)")
            let spent = await pump(5) { self.status.sp < sp0 }
            check("SP is spent by the skill", spent, "sp \(sp0) -> \(status.sp)")
            _ = await kill(target, timeout: 60)
        } else {
            check("use Bash on a monster", false, "no monster")
        }

        // Cooldown: Magnum Break has a 2 s cooldown the server announces with ZC_SKILL_POSTDELAY.
        await heal()
        let coolMark = mark()
        playSession.useShortcut(.skill(skillID: 7, level: 1))
        let cooled = await pump(10) { self.playSession.skillCooldowns[7] != nil }
        let cooldown = playSession.skillCooldowns[7]
        let seconds = cooldown.map { Double($0.duration.components.seconds) + Double($0.duration.components.attoseconds) / 1e18 } ?? 0
        check("skill with a cooldown (Magnum Break: CZ_USE_SKILL, ZC_SKILL_POSTDELAY)", cooled && received("ZC_SKILL_POSTDELAY", since: coolMark) > 0, "cooldown \(String(format: "%.1f", seconds)) s; sent x\(sent("CZ_USE_SKILL", since: coolMark)); ZC_SKILL_POSTDELAY x\(received("ZC_SKILL_POSTDELAY", since: coolMark)); sp \(status.sp)")
        if cooldown != nil {
            check("client cooldown is for the announced duration", abs(seconds - 2.0) < 0.2, "duration \(seconds) s; shortcut cooldown lookup \(playSession.skillCooldown(for: .skill(skillID: 7, level: 1)) != nil)")
        }
        report.summary = "Basic Skill 9, Swordman Bash 5 and Magnum Break 1 learned through the skill window call; Bash on a Poring; Magnum Break cooldown"
        end()
    }

    // MARK: - P3-11 Ground targeting and area skills

    private func p311() async {
        begin("P3-11", "Ground targeting and area skills")
        await gm("@jobchange 2", settle: 0.5)
        let hasSkills = await pump(10) { self.playSession.skillList.skills[19] != nil }
        check("mage skill list after the job change (Cold Bolt 19 present, Bash gone)", hasSkills && self.playSession.skillList.skills[5] == nil, "skills \(playSession.skillList.skills.keys.sorted())")

        let pointsBefore = status.skillPoint
        await gm("@skillpoint 6", settle: 0.4)
        _ = await pump(6) { self.status.skillPoint >= pointsBefore + 6 }
        let coldOK = await learn(19, levels: 1, label: "Cold Bolt")
        let lightningOK = await learn(20, levels: 4, label: "Lightning Bolt")
        let stormOK = await learn(21, levels: 1, label: "Thunderstorm")
        let storm = playSession.skillList.skills[21]
        check("learn Thunderstorm (Cold Bolt 1, Lightning Bolt 4, Thunderstorm 1)", coldOK && lightningOK && stormOK && (storm?.level ?? 0) == 1, "Thunderstorm level \(storm?.level ?? 0), sp \(storm?.spCost ?? 0), range \(storm?.attackRange ?? 0), skill points left \(status.skillPoint)")
        check("client sees Thunderstorm as a ground skill", storm?.isGroundTargetedSkill == true, "flag \(storm?.flag ?? -1)")

        if status.maxSp < 60 {
            await gm("@int 30", settle: 1.0)
        }
        await heal()
        note("sp \(status.sp)/\(status.maxSp)")

        // On a target: the client walks into range, then sends the skill at the monster's cell. Start from a quiet room
        // with one fresh Poring: a monster that was already hit would attack and interrupt the cast.
        say("@killmonster")
        _ = await pump(8) { self.monsters().isEmpty }
        if await ensureMonster(spawn: 1), let target = monsters().first, let scene {
            scene.selectTarget(target)
            let monsterCell = target.gridPosition
            Log.line("Thunderstorm on \(target.name) at \(monsterCell), player at \(scene.player.gridPosition)")
            let cast = await castThunderstorm(sentTimeout: 40, tracking: target.objectID)
            let cells = sentPayloads("CZ_USE_SKILL_TOGROUND", since: cast.mark).map(Self.groundCell)
            let targetCell = cells.first.flatMap { $0 }
            check("ground skill at a selected monster (CZ_USE_SKILL_TOGROUND, ZC_NOTIFY_GROUNDSKILL)", cast.sent && cast.acked, "attempt \(cast.attempts); sent x\(sent("CZ_USE_SKILL_TOGROUND", since: cast.mark)); cell \(targetCell.map { "\($0.x),\($0.y)" } ?? "?") monster was at \(monsterCell.x),\(monsterCell.y) when selected; ZC_USESKILL_ACK (cast bar) x\(received("ZC_USESKILL_ACK", since: cast.mark)) ZC_NOTIFY_GROUNDSKILL x\(received("ZC_NOTIFY_GROUNDSKILL", since: cast.mark))")
            if let targetCell {
                let nearest = cast.targetCells.map { distance($0, targetCell) }.min() ?? Int.max
                check("sent cell is where the target stood (within 1 cell of a position it had while the cast was sent)", nearest <= 1, "sent \(targetCell.x),\(targetCell.y); target cells seen \(cast.targetCells.suffix(6).map { "\($0.x),\($0.y)" })")
            }
            let effectSeen = await pump(3) { !(self.scene?.effects.isEmpty ?? true) }
            note("map effects after the cast: \(self.scene?.effects.count ?? 0) (\(effectSeen ? "seen" : "none"))")
            await pause(2)
        } else {
            check("ground skill at a selected monster", false, "no monster")
        }

        // Without a selection the client casts at the character's own cell.
        await heal()
        if let scene {
            scene.selectTarget(nil)
            // A monster that hits the caster interrupts the cast, so clear the room first (no drops, no exp).
            say("@killmonster")
            _ = await pump(8) { self.monsters().isEmpty }
            await pause(3.5) // the Thunderstorm delay from the first cast
            let ownCell = scene.player.gridPosition
            let cast = await castThunderstorm(sentTimeout: 10)
            let cells = sentPayloads("CZ_USE_SKILL_TOGROUND", since: cast.mark).map(Self.groundCell)
            let cell = cells.first.flatMap { $0 }
            check("ground skill without a target casts at the character's cell", cast.sent && cast.acked && cell == ownCell, "attempt \(cast.attempts); sent cell \(cell.map { "\($0.x),\($0.y)" } ?? "?") own cell \(ownCell.x),\(ownCell.y); ZC_NOTIFY_GROUNDSKILL x\(received("ZC_NOTIFY_GROUNDSKILL", since: cast.mark)); ack failures \(received("ZC_ACK_TOUSESKILL", since: cast.mark))")
        }
        report.summary = "Thunderstorm learned through the skill window call, cast on a selected monster and at the character's own cell"
        end()
    }

    /// Casts Thunderstorm through the shortcut call. A monster that hits the caster interrupts the cast (no
    /// ZC_NOTIFY_GROUNDSKILL follows), so like a player the scenario casts again, at most three times.
    private func castThunderstorm(sentTimeout: TimeInterval, tracking target: GameObjectID? = nil) async -> (mark: Int, attempts: Int, sent: Bool, acked: Bool, targetCells: [SIMD2<Int>]) {
        var result = (mark: mark(), attempts: 0, sent: false, acked: false, targetCells: [SIMD2<Int>]())
        for attempt in 1...3 {
            result.mark = mark()
            result.attempts = attempt
            playSession.useShortcut(.skill(skillID: 21, level: 1))
            let castMark = result.mark
            // A monster walks, so note where the target stood while the request was prepared and sent.
            var cells: [SIMD2<Int>] = []
            let sample = {
                if let target, let cell = self.scene?.objects[target]?.gridPosition, cells.last != cell {
                    cells.append(cell)
                }
            }
            sample()
            result.sent = await pump(sentTimeout) { sample(); return self.sent("CZ_USE_SKILL_TOGROUND", since: castMark) > 0 }
            sample()
            result.targetCells = cells
            result.acked = await pump(8) { self.received("ZC_NOTIFY_GROUNDSKILL", since: castMark) > 0 }
            if result.acked {
                break
            }
            note("Thunderstorm attempt \(attempt) was not carried out (cast interrupted or refused), casting again")
            await pause(4)
        }
        return result
    }

    /// The x and y of a CZ_USE_SKILL_TOGROUND frame: opcode, level, skill id, x, y.
    private static func groundCell(_ payload: [UInt8]) -> SIMD2<Int>? {
        guard payload.count >= 10 else { return nil }
        let x = Int(payload[6]) | Int(payload[7]) << 8
        let y = Int(payload[8]) | Int(payload[9]) << 8
        return SIMD2(x, y)
    }

    // MARK: - NPC helpers

    private func npc(at cell: SIMD2<Int>) -> MapSceneMapObject? {
        scene?.objects.values.first { ($0.type == .npc || $0.type == .npc2) && $0.gridPosition == cell }
    }

    private func dialogText() -> String {
        playSession.dialog?.message ?? ""
    }

    /// Taps an NPC the way the UI does.
    private func tapNPC(_ object: MapSceneMapObject) {
        Log.line("tap npc \(object.objectID) job \(object.job) at \(object.gridPosition)")
        scene?.handleInteraction(.mapObject(objectID: object.objectID))
    }

    /// Waits for a dialog state and returns it.
    private func awaitDialog(timeout: TimeInterval = 15, _ condition: @escaping (NPCDialog) -> Bool) async -> NPCDialog? {
        let ok = await pump(timeout) { self.playSession.dialog.map(condition) ?? false }
        return ok ? playSession.dialog : nil
    }

    /// Goes through a dialog: presses next until a menu or the end, like the dialog window buttons.
    private func advanceToMenu() async -> NPCDialog? {
        for _ in 0..<8 {
            guard let dialog = await awaitDialog({ $0.menu != nil || $0.action != nil }) else { return nil }
            if dialog.menu != nil {
                return dialog
            }
            if dialog.action == .next {
                playSession.requestNextMessage()
                await pause(0.5)
            } else {
                return dialog
            }
        }
        return nil
    }

    // MARK: - P3-08 NPC dialog, shops, storage

    private func p308() async {
        begin("P3-08", "NPC dialog, shops, and storage")
        await gm("@zeny 20000", settle: 0.5)
        _ = await pump(5) { self.status.zeny >= 20000 }
        check("zeny granted for the shop (@zeny)", status.zeny >= 20000, "zeny \(status.zeny)")

        // Tool Dealer in Prontera's inner map, prt_in at 126,76.
        let mapMark = mark()
        await gm("@warp prt_in 126 80", settle: 0.2)
        guard let arrived = await awaitMapChange(since: mapMark) else {
            check("reach the Tool Dealer map (prt_in)", false, "no map change")
            end()
            return
        }
        note("arrived at \(arrived.map) \(arrived.position.x),\(arrived.position.y); npcs in view \(scene?.objects.values.filter { $0.type == .npc || $0.type == .npc2 }.count ?? 0)")

        guard let dealer = npc(at: SIMD2(126, 76)) else {
            check("find the Tool Dealer NPC at 126,76", false, "npcs: \(scene?.objects.values.filter { $0.type == .npc || $0.type == .npc2 }.map { "\($0.objectID)@\($0.gridPosition.x),\($0.gridPosition.y)" } ?? [])")
            end()
            return
        }
        check("find the Tool Dealer NPC at 126,76", true, "object \(dealer.objectID) job \(dealer.job)")

        // Buy.
        let zeny0 = status.zeny
        let potions0 = amount(of: 501)
        let wings0 = amount(of: 601)
        let dealMark = mark()
        tapNPC(dealer)
        let asked = await pump(15) { self.playSession.dealSelectionNPCID != nil }
        check("click a shop NPC: buy or sell choice (CZ_CONTACTNPC, ZC_SELECT_DEALTYPE)", asked, "ZC_SELECT_DEALTYPE x\(received("ZC_SELECT_DEALTYPE", since: dealMark)); CZ_CONTACTNPC x\(sent("CZ_CONTACTNPC", since: dealMark))")
        playSession.selectDealType(.buy)
        let buyList = await pump(10) { self.playSession.npcShop != nil }
        var buyItems: [NPCShopBuyItem] = []
        if case .buy(let items)? = playSession.npcShop {
            buyItems = items
        }
        check("buy list shown (ZC_PC_PURCHASE_ITEMLIST)", buyList && buyItems.contains(where: { $0.itemID == 501 }) && buyItems.contains(where: { $0.itemID == 601 }), "items \(buyItems.map { "\($0.itemID)@\($0.unitPrice)" })")
        let potionPrice = buyItems.first(where: { $0.itemID == 501 })?.unitPrice ?? 0
        let wingPrice = buyItems.first(where: { $0.itemID == 601 })?.unitPrice ?? 0
        let buyMark = mark()
        playSession.purchaseItems([NPCShopPurchase(itemID: 501, amount: 5), NPCShopPurchase(itemID: 601, amount: 3)])
        let bought = await pump(10) { self.amount(of: 501) >= potions0 + 5 && self.amount(of: 601) >= wings0 + 3 }
        let spentZeny = zeny0 - status.zeny
        let expectedSpend = 5 * potionPrice + 3 * wingPrice
        let paid = await pump(5) { zeny0 - self.status.zeny == expectedSpend }
        check("buy 5 Red Potion and 3 Fly Wing (CZ_PC_PURCHASE_ITEMLIST, ZC_PC_PURCHASE_RESULT)", bought && received("ZC_PC_PURCHASE_RESULT", since: buyMark) > 0 && playSession.npcShop == nil, "potions \(potions0) -> \(amount(of: 501)), wings \(wings0) -> \(amount(of: 601)); ZC_PC_PURCHASE_RESULT x\(received("ZC_PC_PURCHASE_RESULT", since: buyMark))")
        check("zeny charged the list price", paid, "zeny \(zeny0) -> \(status.zeny) (spent \(spentZeny), expected \(expectedSpend) = 5 x \(potionPrice) + 3 x \(wingPrice))")

        // Sell.
        await pause(1)
        let zenyBeforeSell = status.zeny
        let potionsBeforeSell = amount(of: 501)
        let sellMark = mark()
        tapNPC(dealer)
        _ = await pump(15) { self.playSession.dealSelectionNPCID != nil }
        playSession.selectDealType(.sell)
        let sellList = await pump(10) { self.playSession.npcShop != nil }
        var sellItems: [NPCShopSellItem] = []
        if case .sell(let items)? = playSession.npcShop {
            sellItems = items
        }
        let potionIndex = firstItem(501)?.index ?? -1
        let sellEntry = sellItems.first(where: { $0.index == potionIndex })
        check("sell list shown (ZC_PC_SELL_ITEMLIST)", sellList && sellEntry != nil, "sellable \(sellItems.map { "\($0.index)@\($0.unitPrice)" }), potion index \(potionIndex)")
        if let sellEntry {
            playSession.sellItems([NPCShopSale(index: sellEntry.index, amount: 2)])
            let sold = await pump(10) { self.amount(of: 501) == potionsBeforeSell - 2 }
            let expectedGain = 2 * sellEntry.unitPrice
            let gained = await pump(5) { self.status.zeny - zenyBeforeSell == expectedGain }
            check("sell 2 Red Potion (CZ_PC_SELL_ITEMLIST, ZC_PC_SELL_RESULT)", sold && received("ZC_PC_SELL_RESULT", since: sellMark) > 0 && playSession.npcShop == nil, "potions \(potionsBeforeSell) -> \(amount(of: 501)); ZC_PC_SELL_RESULT x\(received("ZC_PC_SELL_RESULT", since: sellMark))")
            check("zeny paid the sell price", gained, "zeny \(zenyBeforeSell) -> \(status.zeny) (expected +\(expectedGain))")
        }

        // Storage: open it with the GM command, then move items both ways.
        let storageMark = mark()
        await gm("@storage", settle: 0.2)
        let opened = await pump(10) { self.playSession.storage != nil }
        check("open storage (ZC_INVENTORY_START type 2)", opened, "storage \(playSession.storage?.name ?? "nil"); ZC_INVENTORY_START x\(received("ZC_INVENTORY_START", since: storageMark)); ZC_NOTIFY_STOREITEM_COUNTINFO x\(received("ZC_NOTIFY_STOREITEM_COUNTINFO", since: storageMark))")
        await storageRoundTrip(label: "P3-08")
        report.summary = "Tool Dealer clicked, 5 potions and 3 Fly Wings bought, 2 potions sold, storage put and take"
        end()
    }

    /// With the storage window open: 3 potions in, 3 out, then close.
    private func storageRoundTrip(label: String) async {
        guard playSession.storage != nil, let potion = firstItem(501) else {
            check("\(label) storage: put and take", false, "storage \(playSession.storage != nil), potion \(firstItem(501) != nil)")
            return
        }
        let before = potion.amount
        let putMark = mark()
        playSession.moveItemToStorage(index: potion.index, amount: 3)
        let put = await pump(10) { (self.firstItem(501)?.amount ?? 0) == before - 3 && self.playSession.storage?.items.values.contains(where: { $0.itemID == 501 && $0.amount >= 3 }) == true }
        let stored = playSession.storage?.items.values.first(where: { $0.itemID == 501 })
        check("\(label) storage: put 3 potions in (CZ_MOVE_ITEM_FROM_BODY_TO_STORE, ZC_ADD_ITEM_TO_STORE)", put, "inventory \(before) -> \(firstItem(501)?.amount ?? 0), storage amount \(stored?.amount ?? 0); ZC_ADD_ITEM_TO_STORE x\(received("ZC_ADD_ITEM_TO_STORE", since: putMark)); ZC_NOTIFY_STOREITEM_COUNTINFO x\(received("ZC_NOTIFY_STOREITEM_COUNTINFO", since: putMark))")
        if let stored {
            let takeMark = mark()
            playSession.moveItemFromStorage(index: stored.index, amount: 3)
            let took = await pump(10) { (self.firstItem(501)?.amount ?? 0) == before && self.playSession.storage?.items.values.contains(where: { $0.itemID == 501 }) != true }
            check("\(label) storage: take 3 potions out (CZ_MOVE_ITEM_FROM_STORE_TO_BODY, ZC_DELETE_ITEM_FROM_STORE)", took, "inventory \(firstItem(501)?.amount ?? 0), storage has potion \(playSession.storage?.items.values.contains(where: { $0.itemID == 501 }) == true); ZC_DELETE_ITEM_FROM_STORE x\(received("ZC_DELETE_ITEM_FROM_STORE", since: takeMark))")
        }
        let closeMark = mark()
        playSession.closeStorage()
        let closed = await pump(5) { self.playSession.storage == nil }
        check("\(label) storage: close (CZ_CLOSE_STORE)", closed && sent("CZ_CLOSE_STORE", since: closeMark) > 0, "CZ_CLOSE_STORE x\(sent("CZ_CLOSE_STORE", since: closeMark))")
    }

    // MARK: - P3-09 Kafra

    private func kafraMenuIndex(_ dialog: NPCDialog, containing text: String) -> Int? {
        dialog.menu?.firstIndex(where: { $0.localizedCaseInsensitiveContains(text) })
    }

    /// Reads the dialog to its end and closes it, as the window's Close button does.
    private func finishDialog() async {
        for _ in 0..<8 {
            guard let dialog = await awaitDialog(timeout: 8, { $0.action != nil || $0.menu != nil }) else { return }
            if dialog.menu != nil { return }
            if dialog.action == .next {
                playSession.requestNextMessage()
                await pause(0.5)
            } else {
                playSession.closeDialog()
                await pause(0.6)
                return
            }
        }
    }

    private func p309() async {
        begin("P3-09", "Kafra save, teleport, and storage")
        await gm("@zeny 20000", settle: 0.5)

        let mapMark = mark()
        await gm("@warp prontera 151 33", settle: 0.2)
        guard let arrived = await awaitMapChange(since: mapMark) else {
            check("reach the Prontera Kafra", false, "no map change")
            end()
            return
        }
        note("arrived at \(arrived.map) \(arrived.position.x),\(arrived.position.y)")
        guard let kafra = npc(at: SIMD2(151, 29)) else {
            check("find the Kafra Employee at 151,29", false, "npcs: \(scene?.objects.values.filter { $0.type == .npc || $0.type == .npc2 }.map { "\($0.objectID)@\($0.gridPosition.x),\($0.gridPosition.y)" } ?? [])")
            end()
            return
        }
        check("find the Kafra Employee at 151,29", true, "object \(kafra.objectID) job \(kafra.job)")

        // NPC dialog (P3-08): text, next, menu, cancel, close.
        let talkMark = mark()
        tapNPC(kafra)
        let said = await awaitDialog({ !$0.message.isEmpty })
        check("NPC dialog text (CZ_CONTACTNPC, ZC_SAY_DIALOG)", said != nil, "ZC_SAY_DIALOG x\(received("ZC_SAY_DIALOG", since: talkMark)); text \"\(dialogText().replacingOccurrences(of: "\n", with: " / ").prefix(80))\"")
        let nextButton = await awaitDialog({ $0.action == .next || $0.menu != nil })
        if nextButton?.action == .next {
            let nextMark = mark()
            playSession.requestNextMessage()
            let menuAfterNext = await awaitDialog({ $0.menu != nil })
            check("dialog next button (CZ_REQ_NEXT_SCRIPT, ZC_MENU_LIST)", menuAfterNext != nil, "CZ_REQ_NEXT_SCRIPT x\(sent("CZ_REQ_NEXT_SCRIPT", since: nextMark)); menu \(menuAfterNext?.menu ?? [])")
        }
        guard let menu = playSession.dialog?.menu else {
            check("Kafra menu", false, "no menu: dialog \(dialogText())")
            end()
            return
        }
        note("Kafra menu: \(menu)")
        let cancelMark = mark()
        playSession.cancelMenu()
        await pause(1.0)
        check("cancel the menu (CZ_CHOOSE_MENU 255) ends the conversation", sent("CZ_CHOOSE_MENU", since: cancelMark) > 0 && playSession.dialog == nil, "CZ_CHOOSE_MENU x\(sent("CZ_CHOOSE_MENU", since: cancelMark)); dialog open \(playSession.dialog != nil)")
        await pause(1.0)

        // Save.
        tapNPC(kafra)
        if var menuDialog = await advanceToMenu(), let index = kafraMenuIndex(menuDialog, containing: "Save") {
            let saveMark = mark()
            playSession.selectMenu(UInt8(index + 1))
            await finishDialog()
            menuDialog = playSession.dialog ?? menuDialog
            check("Kafra Save (CZ_CHOOSE_MENU \"Save\", dialog ends)", sent("CZ_CHOOSE_MENU", since: saveMark) > 0, "menu index \(index + 1); ZC_SAY_DIALOG x\(received("ZC_SAY_DIALOG", since: saveMark)); ZC_CLOSE_DIALOG x\(received("ZC_CLOSE_DIALOG", since: saveMark))")
        } else {
            check("Kafra Save", false, "no Save entry in the menu")
        }
        await pause(1.0)

        // Storage through the menu.
        let zenyBeforeStorage = status.zeny
        tapNPC(kafra)
        if let menuDialog = await advanceToMenu(), let index = kafraMenuIndex(menuDialog, containing: "Storage") {
            let storageMark = mark()
            playSession.selectMenu(UInt8(index + 1))
            // The script says "let me open your storage", closes the window (close2), then opens the storage.
            for _ in 0..<6 where playSession.storage == nil {
                if let dialog = await awaitDialog(timeout: 5, { $0.action != nil }) {
                    if dialog.action == .next { playSession.requestNextMessage() } else { playSession.closeDialog() }
                    await pause(0.6)
                }
            }
            let opened = await pump(10) { self.playSession.storage != nil }
            check("Kafra Use Storage opens the storage (fee 40 zeny)", opened, "storage \(playSession.storage?.name ?? "nil"); zeny \(zenyBeforeStorage) -> \(status.zeny); ZC_INVENTORY_START x\(received("ZC_INVENTORY_START", since: storageMark))")
            await storageRoundTrip(label: "P3-09")
        } else {
            check("Kafra Use Storage", false, "no Storage entry in the menu")
        }
        await pause(1.0)

        // Teleport service.
        let zenyBeforeTeleport = status.zeny
        tapNPC(kafra)
        if let menuDialog = await advanceToMenu(), let index = kafraMenuIndex(menuDialog, containing: "Teleport") {
            playSession.selectMenu(UInt8(index + 1))
            await finishDialogToMenu()
            if let destinations = playSession.dialog?.menu, let geffen = kafraMenuIndex(NPCDialog(npcID: 0, message: "", menu: destinations), containing: "Geffen") {
                note("teleport destinations: \(destinations)")
                let teleportMark = mark()
                playSession.selectMenu(UInt8(geffen + 1))
                let changed = await awaitMapChange(since: teleportMark)
                check("Kafra teleport to Geffen (CZ_CHOOSE_MENU, ZC_NPCACK_MAPMOVE, map load)", changed?.map == "geffen.rsw", "map \(changed?.map ?? "none") at \(changed.map { "\($0.position.x),\($0.position.y)" } ?? "?"); zeny \(zenyBeforeTeleport) -> \(status.zeny); ZC_NPCACK_MAPMOVE x\(received("ZC_NPCACK_MAPMOVE", since: teleportMark))")
                // The script ends right after the warp with its dialog still open (`mes`, `select`, `warp`, `end`, no
                // `close`). The window must be gone on the new map and the server must let the player act at once: no
                // button is pressed here.
                check("Kafra dialog window is closed after the warp (no click needed)", playSession.dialog == nil, "dialog \(playSession.dialog.map { "open: \"\($0.message.replacingOccurrences(of: "\n", with: " / ").prefix(60))\" action \(String(describing: $0.action))" } ?? "closed"); ZC_CLOSE_DIALOG x\(received("ZC_CLOSE_DIALOG", since: teleportMark)), ZC_CLEAR_DIALOG x\(received("ZC_CLEAR_DIALOG", since: teleportMark)), CZ_CLOSE_DIALOG x\(sent("CZ_CLOSE_DIALOG", since: teleportMark))")
                await checkWalkWorks("walking works right after the Kafra warp, dialog never dismissed (CZ_REQUEST_MOVE, ZC_NOTIFY_PLAYERMOVE)")
                await checkItemUseWorks("an item works right after the Kafra warp (CZ_USE_ITEM, ZC_USE_ITEM_ACK)")
            } else {
                check("Kafra teleport to Geffen", false, "no destination list: dialog \(dialogText())")
            }
        } else {
            check("Kafra teleport to Geffen", false, "no Teleport Service entry in the menu")
        }
        report.summary = "Prontera Kafra: dialog, Save, Use Storage (put/take), Teleport Service to Geffen, then walk and use an item with no dialog click"
        end()
    }

    /// Asks the server to walk to a random reachable cell a few cells away and checks that it answers and the player
    /// arrives. The server ignores `CZ_REQUEST_MOVE` while an NPC script is attached to the player.
    private func checkWalkWorks(_ name: String) async {
        guard let scene = self.scene else {
            check(name, false, "no scene")
            return
        }
        let origin = scene.player.gridPosition
        var target: SIMD2<Int>?
        for _ in 0..<80 {
            let candidate = SIMD2(origin.x + Int.random(in: -6...6), origin.y + Int.random(in: -6...6))
            if candidate != origin, distance(candidate, origin) >= 3, scene.mapGrid.contains(candidate), scene.mapGrid[candidate].isWalkable, scene.pathFinder.canRequestMove(from: origin, to: candidate) {
                target = candidate
                break
            }
        }
        guard let target else {
            check(name, false, "no walkable cell near \(origin.x),\(origin.y)")
            return
        }
        let walkMark = mark()
        scene.handleInteraction(.ground(position: target))
        let walked = await pump(15) { self.received("ZC_NOTIFY_PLAYERMOVE", since: walkMark) > 0 && self.scene?.player.gridPosition == target }
        check(name, walked, "from \(origin.x),\(origin.y) to \(target.x),\(target.y), now \(self.scene?.player.gridPosition.x ?? -1),\(self.scene?.player.gridPosition.y ?? -1); CZ_REQUEST_MOVE x\(sent("CZ_REQUEST_MOVE", since: walkMark)), ZC_NOTIFY_PLAYERMOVE x\(received("ZC_NOTIFY_PLAYERMOVE", since: walkMark)); dialog \(playSession.dialog == nil ? "closed" : "open")")
    }

    /// Eats a Red Potion: the server refuses item use while an NPC script is attached.
    private func checkItemUseWorks(_ name: String) async {
        if firstItem(501) == nil {
            await gm("@item 501 5", settle: 0.5)
            _ = await pump(8) { self.firstItem(501) != nil }
        }
        guard let potion = firstItem(501) else {
            check(name, false, "no Red Potion")
            return
        }
        let before = potion.amount
        let useMark = mark()
        playSession.useItem(at: potion.index)
        let used = await pump(8) { (self.firstItem(501)?.amount ?? 0) < before }
        check(name, used, "Red Potions \(before) -> \(firstItem(501)?.amount ?? 0); CZ_USE_ITEM x\(sent("CZ_USE_ITEM", since: useMark)), ZC_USE_ITEM_ACK x\(received("ZC_USE_ITEM_ACK", since: useMark))")
    }

    /// After choosing a Kafra entry: next buttons until the next menu.
    private func finishDialogToMenu() async {
        for _ in 0..<6 {
            guard let dialog = await awaitDialog(timeout: 8, { $0.action != nil || $0.menu != nil }) else { return }
            if dialog.menu != nil { return }
            if dialog.action == .next {
                playSession.requestNextMessage()
                await pause(0.5)
            } else {
                return
            }
        }
    }

    // MARK: - P3-02 Map transitions, portals, teleports

    private func p302() async {
        begin("P3-02", "Map transitions, portals, and teleports")
        // Teleport items: Fly Wing (same map, random cell) and Butterfly Wing (save point).
        await gm("@item 602 2", settle: 0.5)
        _ = await pump(8) { self.firstItem(602) != nil }
        guard let scene0 = scene else {
            check("scene before teleport", false, "no scene")
            end()
            return
        }
        let map0 = scene0.mapName
        let pos0 = scene0.player.gridPosition

        if let wing = firstItem(601) {
            let wings0 = wing.amount
            let flyMark = mark()
            Log.line("Fly Wing on \(map0) at \(pos0)")
            playSession.useItem(at: wing.index)
            let result = await awaitMapChange(since: flyMark, timeout: 30)
            let wingsAfter = firstItem(601)?.amount ?? 0
            let moved = result.map { $0.map == map0 && distance($0.position, pos0) > 0 } ?? false
            check("Fly Wing teleports on the same map (CZ_USE_ITEM, ZC_NPCACK_MAPMOVE, jump)", moved && wingsAfter == wings0 - 1, "\(map0) \(pos0.x),\(pos0.y) -> \(result?.map ?? "none") \(result.map { "\($0.position.x),\($0.position.y)" } ?? "?"); Fly Wings \(wings0) -> \(wingsAfter); ZC_NPCACK_MAPMOVE x\(received("ZC_NPCACK_MAPMOVE", since: flyMark)); CZ_NOTIFY_ACTORINIT x\(sent("CZ_NOTIFY_ACTORINIT", since: flyMark))")

            // The scene still works after the jump: a walk request is answered.
            if let scene = self.scene {
                let origin = scene.player.gridPosition
                var target: SIMD2<Int>?
                for _ in 0..<60 {
                    let candidate = SIMD2(origin.x + Int.random(in: -6...6), origin.y + Int.random(in: -6...6))
                    if candidate != origin, scene.mapGrid.contains(candidate), scene.mapGrid[candidate].isWalkable, scene.pathFinder.canRequestMove(from: origin, to: candidate) {
                        target = candidate
                        break
                    }
                }
                if let target {
                    let walkMark = mark()
                    scene.handleInteraction(.ground(position: target))
                    let walked = await pump(15) { self.received("ZC_NOTIFY_PLAYERMOVE", since: walkMark) > 0 && self.scene?.player.gridPosition == target }
                    check("walking works after the teleport (CZ_REQUEST_MOVE, ZC_NOTIFY_PLAYERMOVE)", walked, "from \(origin.x),\(origin.y) to \(target.x),\(target.y), now \(self.scene?.player.gridPosition.x ?? -1),\(self.scene?.player.gridPosition.y ?? -1)")
                }
            }
        } else {
            check("Fly Wing teleport", false, "no Fly Wing (bought in P3-08)")
        }

        // Butterfly Wing returns to the save point set at the Kafra (prontera 150,33), which is another map.
        if let wing = firstItem(602) {
            let mapBefore = scene?.mapName ?? ""
            let butterflyMark = mark()
            playSession.useItem(at: wing.index)
            let result = await awaitMapChange(since: butterflyMark, timeout: 90)
            let expectedNearSave = result.map { $0.map == "prontera.rsw" && distance($0.position, SIMD2(150, 33)) <= 3 } ?? false
            check("Butterfly Wing returns to the save point on another map (ZC_NPCACK_MAPMOVE, map load)", expectedNearSave, "\(mapBefore) -> \(result?.map ?? "none") \(result.map { "\($0.position.x),\($0.position.y)" } ?? "?") (Kafra saved prontera 150,33); ZC_NPCACK_MAPMOVE x\(received("ZC_NPCACK_MAPMOVE", since: butterflyMark))")
        } else {
            check("Butterfly Wing teleport", false, "no Butterfly Wing")
        }

        // GM warp to another map.
        let warpMark = mark()
        await gm("@warp prt_fild08 170 200", settle: 0.2)
        let warped = await awaitMapChange(since: warpMark, timeout: 90)
        check("@warp to a field map (ZC_NPCACK_MAPMOVE, map load)", warped?.map == "prt_fild08.rsw", "map \(warped?.map ?? "none") at \(warped.map { "\($0.position.x),\($0.position.y)" } ?? "?")")
        report.summary = "Fly Wing (same map), Butterfly Wing (to the Kafra save point on Prontera) and @warp (field map)"
        end()
    }

    // MARK: - P3-13 Audio

    private func p313() async {
        begin("P3-13", "Audio: BGM and sound effects")
        guard options.withAudio else {
            report.skipped = true
            note("run with --with-audio; the resource provider answers \"not found\" for audio otherwise")
            end()
            return
        }
        let resourceManager = gameSession.context.resourceManager
        let mp3Table = await resourceManager.mp3NameTable()
        let requests = stats.audioSnapshot

        let bgmRequests = requests.filter { $0.key.hasPrefix("BGM/") }
        let wavRequests = requests.filter { $0.key.lowercased().hasSuffix(".wav") }
        check("the client requested BGM while playing", !bgmRequests.isEmpty, "\(bgmRequests.count) BGM file(s): \(bgmRequests.keys.sorted())")
        let bgmMissing = bgmRequests.filter { ($0.value["found"] as? Bool) != true }
        check("every requested BGM file resolved", bgmMissing.isEmpty && !bgmRequests.isEmpty, "missing: \(bgmMissing.keys.sorted())")

        // Each map the run visited: the name table maps it to an mp3, which resolves and decodes as the player does.
        let mapsToCheck = Array(Set(visitedMaps + stats.mapsVisited.map { $0.lowercased() })).sorted()
        var bgmRows: [String] = []
        var bgmOK = true
        for map in mapsToCheck {
            let rsw = map.hasSuffix(".rsw") ? map : map + ".rsw"
            guard let mp3 = mp3Table.mp3Name(forMapName: rsw) else {
                bgmRows.append("\(rsw): no mp3nametable entry")
                bgmOK = false
                continue
            }
            do {
                let data = try await resourceManager.contentsOfResource(at: ResourcePath(components: ["BGM", mp3]))
                let player = try AVAudioPlayer(data: data)
                let ok = player.duration > 1 && data.count > 10_000
                bgmOK = bgmOK && ok
                bgmRows.append("\(rsw): \(mp3) \(data.count) bytes \(String(format: "%.0f", player.duration)) s \(ok ? "ok" : "BAD")")
            } catch {
                bgmOK = false
                bgmRows.append("\(rsw): \(mp3) failed \(error)")
            }
        }
        check("BGM of each visited map resolves through mp3nametable.txt and decodes", bgmOK && !mapsToCheck.isEmpty, bgmRows.joined(separator: "; "))

        // Sound effects the client asked for while playing.
        var decoded = 0
        var undecodable: [String] = []
        for (path, row) in wavRequests.sorted(by: { $0.key < $1.key }) where (row["found"] as? Bool) == true {
            let name = path.components(separatedBy: "/").last ?? path
            if let data = try? await resourceManager.contentsOfResource(at: ResourcePath(components: ["data", "wav", name])),
               await AVAudioPCMBuffer.buffer(from: data, format: GameAudio.format) != nil {
                decoded += 1
            } else {
                undecodable.append(path)
            }
        }
        let wavFound = wavRequests.filter { ($0.value["found"] as? Bool) == true }
        let wavMissing = wavRequests.filter { ($0.value["found"] as? Bool) != true }
        check("sound effects requested by the client resolve and decode", wavFound.count >= 3 && undecodable.isEmpty, "requested \(wavRequests.count), resolved \(wavFound.count), decoded \(decoded), undecodable \(undecodable), missing \(wavMissing.count)")
        if !wavMissing.isEmpty {
            note("sound names the client asked for that the GRF does not hold: \(wavMissing.keys.sorted().prefix(20))")
        }

        // Fixed sounds the UI plays by name.
        var fixed: [String] = []
        var fixedOK = true
        for (label, name) in [("UI button sound (버튼소리.wav)", K2L("버튼소리.wav")), ("_heal_effect.wav", "_heal_effect.wav")] {
            if let data = try? await resourceManager.contentsOfResource(at: ResourcePath(components: ["data", "wav", name])),
               await AVAudioPCMBuffer.buffer(from: data, format: GameAudio.format) != nil {
                fixed.append("\(label) ok")
            } else {
                fixed.append("\(label) MISSING")
                fixedOK = false
            }
        }
        check("UI button sound and heal effect resolve and decode", fixedOK, fixed.joined(separator: ", "))
        note("playback is not judged here: audio preferences are \(options.audible ? "on" : "off") for this run, so nothing was played")
        report.summary = "BGM and wav requests recorded from the whole run; BGM and wav files decode"
        end()
    }
}
