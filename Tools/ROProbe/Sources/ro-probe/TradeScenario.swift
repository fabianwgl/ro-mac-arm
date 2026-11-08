import Foundation
import RagnarokConstants
@testable import RagnarokGame
import RagnarokModels
import RagnarokPackets
import RagnarokResources
import simd

/// Two real clients in one process trade with each other on a live rAthena (`--trade-test`).
///
/// Both log in as administrators (`trade1`, `trade2`, group 99) so `@item`, `@zeny` and `@warp` set the scene up,
/// then they drive the same `MapScene` and `PlaySession` entry points the UI uses: select the other player,
/// request the trade, accept, add items and zeny, OK, Trade. Three rounds run on one pair of characters:
/// a declined request, a cancelled trade and a completed trade. After the completed trade both clients log out
/// and in again, and the inventories the server sends must equal what the clients had.
///
/// The packet tap is not used: two clients would share its counters. Results go to stdout and `--json`.
@MainActor
final class TradeScenario {
    static let redPotion = 501
    static let orangePotion = 502

    struct Snapshot: Equatable {
        var zeny: Int
        var items: [Int: Int]

        var json: [String: Any] {
            ["zeny": zeny, "items": Dictionary(uniqueKeysWithValues: items.map { (String($0.key), $0.value) })]
        }
    }

    @MainActor
    final class Client {
        let label: String
        let user: String
        let password: String
        let characterName: String
        var gameSession: GameSession?
        var lastAccountID: UInt32 = 0
        var lastMessages: [String] = []

        init(label: String, user: String, password: String, characterName: String) {
            self.label = label
            self.user = user
            self.password = password
            self.characterName = characterName
        }

        var playSession: PlaySession? {
            gameSession?.playSession
        }

        var scene: MapScene? {
            gameSession?.mapScene
        }

        var accountID: UInt32 {
            playSession?.account.accountID ?? lastAccountID
        }

        var snapshot: Snapshot {
            guard let playSession else {
                return Snapshot(zeny: 0, items: [:])
            }
            var items: [Int: Int] = [:]
            for item in playSession.inventory.items.values {
                items[item.itemID, default: 0] += item.amount
            }
            return Snapshot(zeny: playSession.playerStatus.zeny, items: items)
        }

        /// The inventory index of the first stack of an item.
        func index(ofItem itemID: Int) -> Int? {
            playSession?.inventory.items.values.filter { $0.itemID == itemID }.map(\.index).min()
        }

        var messages: [String] {
            playSession?.messageCenter.messages.map(\.content) ?? lastMessages
        }
    }

    let options: Options
    let resourceManager: ResourceManager
    let a: Client
    let b: Client

    private var checks: [[String: Any]] = []
    private var snapshots: [String: Any] = [:]
    private var notes: [String] = []
    private var pumping = true

    init(options: Options, resourceManager: ResourceManager) {
        self.options = options
        self.resourceManager = resourceManager
        self.a = Client(label: "A", user: "trade1", password: "trade1", characterName: "TradeOne")
        self.b = Client(label: "B", user: "trade2", password: "trade2", characterName: "TradeTwo")
    }

    // MARK: - Entry point

    static func run(options: Options) async -> Bool {
        let clientURL = URL(fileURLWithPath: options.clientDir, isDirectory: true)
        guard FileManager.default.fileExists(atPath: clientURL.appending(path: "data.grf").path(percentEncoded: false)) else {
            Log.line("data.grf not found in \(options.clientDir)")
            return false
        }
        let provider = ClientFilesProvider(url: clientURL, allowAudio: false)
        let scenario = TradeScenario(options: options, resourceManager: ResourceManager(resourceProvider: provider))
        return await scenario.execute()
    }

    private func execute() async -> Bool {
        let started = Date()
        let pump = Task { @MainActor in
            while self.pumping {
                for client in [self.a, self.b] {
                    // What the app's render loop calls every frame, without drawing.
                    client.playSession?.mapRuntime?.update(at: .now, renderTime: ProcessInfo.processInfo.systemUptime)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        var failure: String?
        do {
            try await scenario()
        } catch {
            failure = "\(error)"
            Log.line("trade test aborted: \(error)")
            check("scenario ran to the end", false, "\(error)")
        }

        pumping = false
        await pump.value
        for client in [a, b] {
            client.lastAccountID = client.accountID
            client.lastMessages = client.messages
            client.gameSession?.stop()
        }

        let passed = failure == nil && checks.allSatisfy { ($0["passed"] as? Bool) == true }
        report(passed: passed, seconds: Date().timeIntervalSince(started))
        return passed
    }

    // MARK: - Scenario

    private func scenario() async throws {
        Log.line("trade test: connecting \(a.user)/\(a.characterName) and \(b.user)/\(b.characterName)")
        try await connect(a)
        try await connect(b)

        try await meetOnProntera()
        try await giveStartingGoods()

        try await declinedRound()
        try await cancelledRound()
        try await completedRound()
        try await reloginRound()
    }

    /// Both characters stand on the same cell of one map, close enough for the server's 2 cell rule.
    ///
    /// A warp is only sent when needed: the server drops chat that arrives while a map change is in flight,
    /// and a warp to the map the character is on looks like no change to wait for.
    private func meetOnProntera() async throws {
        if a.scene?.mapName.hasPrefix("prontera") != true {
            send(a, "@warp prontera 156 191")
            try await wait("A on prontera") { self.a.scene?.mapName.hasPrefix("prontera") == true }
            try await Task.sleep(for: .seconds(2))
        }
        guard let place = a.scene?.player.gridPosition else {
            throw ScenarioError("A has no position")
        }
        if !isOnPronteraNear(place) {
            send(b, "@warp prontera \(place.x) \(place.y)")
            try await wait("B next to A") { self.isOnPronteraNear(place) }
            try await Task.sleep(for: .seconds(2))
        }
        try await wait("A sees B and B sees A", timeout: 60) {
            self.a.scene?.objects[self.b.accountID] != nil && self.b.scene?.objects[self.a.accountID] != nil
        }
        let distance = chebyshev(a.scene?.player.gridPosition, b.scene?.player.gridPosition)
        check("both players stand within 2 cells", distance <= 2, "A \(a.scene?.player.gridPosition ?? .zero), B \(b.scene?.player.gridPosition ?? .zero), distance \(distance)")
        check("the other player's name is on the map object", a.scene?.objects[b.accountID]?.name == b.characterName && b.scene?.objects[a.accountID]?.name == a.characterName,
              "A sees \(a.scene?.objects[b.accountID]?.name ?? "-"), B sees \(b.scene?.objects[a.accountID]?.name ?? "-")")
    }

    private func isOnPronteraNear(_ place: SIMD2<Int>) -> Bool {
        b.scene?.mapName.hasPrefix("prontera") == true && chebyshev(b.scene?.player.gridPosition, place) <= 2
    }

    private func giveStartingGoods() async throws {
        // New characters have no Basic Skill, which rAthena wants to trade (basic_skill_check). A skill point from
        // @skpoint and the same upgrade request the skill window sends give it.
        for client in [a, b] where (client.playSession?.skillList.skills[Trade.basicSkillID]?.level ?? 0) < 1 {
            send(client, "@skpoint 1")
        }
        try await wait("a skill point on both") {
            (self.a.playSession?.playerStatus.skillPoint ?? 0) >= 1 || (self.a.playSession?.skillList.skills[Trade.basicSkillID]?.level ?? 0) >= 1
        }
        try await wait("a skill point on B") {
            (self.b.playSession?.playerStatus.skillPoint ?? 0) >= 1 || (self.b.playSession?.skillList.skills[Trade.basicSkillID]?.level ?? 0) >= 1
        }
        for client in [a, b] where (client.playSession?.skillList.skills[Trade.basicSkillID]?.level ?? 0) < 1 {
            client.playSession?.upgradeSkillLevel(skillID: Trade.basicSkillID)
        }
        try await wait("Basic Skill on both") {
            (self.a.playSession?.skillList.skills[Trade.basicSkillID]?.level ?? 0) >= 1
                && (self.b.playSession?.skillList.skills[Trade.basicSkillID]?.level ?? 0) >= 1
        }

        let before = (a.snapshot, b.snapshot)
        send(a, "@item \(Self.redPotion) 20")
        send(a, "@zeny 5000")
        send(b, "@item \(Self.orangePotion) 10")
        send(b, "@zeny 3000")
        try await wait("goods arrive") {
            self.a.snapshot.items[Self.redPotion, default: 0] >= before.0.items[Self.redPotion, default: 0] + 20
                && self.a.snapshot.zeny >= before.0.zeny + 5000
                && self.b.snapshot.items[Self.orangePotion, default: 0] >= before.1.items[Self.orangePotion, default: 0] + 10
                && self.b.snapshot.zeny >= before.1.zeny + 3000
        }
        snapshots["start"] = ["A": a.snapshot.json, "B": b.snapshot.json]
        Log.line("goods ready: A \(a.snapshot), B \(b.snapshot)")
    }

    // MARK: - Rounds

    /// A asks, B declines.
    private func declinedRound() async throws {
        Log.line("round 1: declined request")
        let (startA, startB) = (a.snapshot, b.snapshot)
        try requestTrade(from: a, to: b)
        try await wait("B sees the request") { self.b.playSession?.trade.incomingRequest != nil }
        check("B's prompt names A", b.playSession?.trade.incomingRequest?.name == a.characterName && b.playSession?.trade.incomingRequest?.accountID == a.accountID,
              "\(String(describing: b.playSession?.trade.incomingRequest))")

        let messagesBefore = a.messages.count
        b.playSession?.answerTradeRequest(accept: false)
        try await wait("A hears the decline") { self.a.messages.count > messagesBefore && self.a.messages.last?.contains("declined") == true }
        try await Task.sleep(for: .milliseconds(500))
        check("declined request opens no trade", a.playSession?.trade.current == nil && b.playSession?.trade.current == nil && a.playSession?.trade.outgoingRequest == nil,
              "A message: \(a.messages.last ?? "-")")
        check("declined request changes no inventory", a.snapshot == startA && b.snapshot == startB, "")
    }

    /// Both offer something, A cancels, everything comes back.
    private func cancelledRound() async throws {
        Log.line("round 2: cancelled trade")
        let (startA, startB) = (a.snapshot, b.snapshot)
        try await openTrade(from: a, to: b)

        guard let redIndex = a.index(ofItem: Self.redPotion), let orangeIndex = b.index(ofItem: Self.orangePotion) else {
            throw ScenarioError("goods missing")
        }
        a.playSession?.offerTradeItem(index: redIndex, amount: 5)
        a.playSession?.offerTradeZeny(100)
        b.playSession?.offerTradeItem(index: orangeIndex, amount: 2)

        try await wait("offers show on both sides") {
            self.a.playSession?.trade.current?.mine.offers.first?.amount == 5
                && self.b.playSession?.trade.current?.theirs.offers.first?.amount == 5
                && self.b.playSession?.trade.current?.theirs.zeny == 100
                && self.a.playSession?.trade.current?.theirs.offers.first?.amount == 2
        }
        check("offered items leave the offerer's inventory list", a.snapshot.items[Self.redPotion] == startA.items[Self.redPotion, default: 0] - 5 && b.snapshot.items[Self.orangePotion] == startB.items[Self.orangePotion, default: 0] - 2,
              "A red \(a.snapshot.items[Self.redPotion] ?? 0) of \(startA.items[Self.redPotion] ?? 0), B orange \(b.snapshot.items[Self.orangePotion] ?? 0) of \(startB.items[Self.orangePotion] ?? 0)")
        check("partner sees the right item ids", b.playSession?.trade.current?.theirs.offers.first?.itemID == Self.redPotion && a.playSession?.trade.current?.theirs.offers.first?.itemID == Self.orangePotion, "")

        a.playSession?.cancelTrade()
        try await wait("both windows close") { self.a.playSession?.trade.current == nil && self.b.playSession?.trade.current == nil }
        try await wait("items come back", timeout: 20) { self.a.snapshot == startA && self.b.snapshot == startB }
        check("cancel restores both inventories and zeny", a.snapshot == startA && b.snapshot == startB, "A \(a.snapshot) B \(b.snapshot)")
        check("B is told about the cancel", b.messages.contains("The trade was cancelled."), "")
    }

    /// The trade that moves two items and zeny both ways.
    private func completedRound() async throws {
        Log.line("round 3: completed trade")
        let (startA, startB) = (a.snapshot, b.snapshot)
        snapshots["beforeTrade"] = ["A": startA.json, "B": startB.json]
        try await openTrade(from: a, to: b)

        guard let redIndex = a.index(ofItem: Self.redPotion), let orangeIndex = b.index(ofItem: Self.orangePotion) else {
            throw ScenarioError("goods missing")
        }
        a.playSession?.offerTradeItem(index: redIndex, amount: 10)
        a.playSession?.offerTradeZeny(2000)
        b.playSession?.offerTradeItem(index: orangeIndex, amount: 4)
        b.playSession?.offerTradeZeny(500)

        try await wait("offers show on both sides") {
            self.a.playSession?.trade.current?.mine.offers.first?.amount == 10
                && self.b.playSession?.trade.current?.mine.offers.first?.amount == 4
                && self.a.playSession?.trade.current?.theirs.offers.first?.amount == 4
                && self.b.playSession?.trade.current?.theirs.offers.first?.amount == 10
                && self.a.playSession?.trade.current?.theirs.zeny == 500
                && self.b.playSession?.trade.current?.theirs.zeny == 2000
        }

        a.playSession?.confirmTrade()
        check("Trade before OK does nothing", a.playSession?.trade.current?.mine.hasConfirmed == false, "")

        a.playSession?.lockTrade()
        try await wait("A locked on both screens") {
            self.a.playSession?.trade.current?.mine.isLocked == true && self.b.playSession?.trade.current?.theirs.isLocked == true
        }
        check("locked side cannot add", a.playSession?.trade.current?.canChangeOffer == false, "")
        b.playSession?.lockTrade()
        try await wait("both locked") {
            self.a.playSession?.trade.current?.isBothLocked == true && self.b.playSession?.trade.current?.isBothLocked == true
        }
        check("both sides can confirm", a.playSession?.trade.current?.canConfirm == true && b.playSession?.trade.current?.canConfirm == true, "")

        a.playSession?.confirmTrade()
        try await Task.sleep(for: .milliseconds(500))
        check("one confirmation does not finish the trade", a.playSession?.trade.current != nil && b.playSession?.trade.current != nil, "")
        b.playSession?.confirmTrade()
        try await wait("both windows close") { self.a.playSession?.trade.current == nil && self.b.playSession?.trade.current == nil }

        var expectedA = startA
        expectedA.items[Self.redPotion, default: 0] -= 10
        expectedA.items[Self.orangePotion, default: 0] += 4
        expectedA.zeny += -2000 + 500
        var expectedB = startB
        expectedB.items[Self.redPotion, default: 0] += 10
        expectedB.items[Self.orangePotion, default: 0] -= 4
        expectedB.zeny += 2000 - 500

        try await wait("inventories settle", timeout: 20) { self.a.snapshot == expectedA && self.b.snapshot == expectedB }
        check("A holds the orange potions and 1500 less zeny", a.snapshot == expectedA, "got \(a.snapshot), expected \(expectedA)")
        check("B holds the red potions and 1500 more zeny", b.snapshot == expectedB, "got \(b.snapshot), expected \(expectedB)")
        check("both are told the trade is complete", a.messages.contains("The trade is complete.") && b.messages.contains("The trade is complete."), "")
        snapshots["afterTrade"] = ["A": a.snapshot.json, "B": b.snapshot.json]
    }

    /// Fresh logins: what the server stored equals what the clients showed after the trade.
    private func reloginRound() async throws {
        Log.line("round 4: relogin and compare with the server's inventory")
        let (shownA, shownB) = (a.snapshot, b.snapshot)
        a.gameSession?.stop()
        b.gameSession?.stop()
        a.gameSession = nil
        b.gameSession = nil
        // Let the map server notice that both are gone and save them.
        try await Task.sleep(for: .seconds(6))

        try await connect(a)
        try await connect(b)
        try await wait("inventories are loaded") { self.a.snapshot.items.isEmpty == false && self.b.snapshot.items.isEmpty == false }
        try await Task.sleep(for: .seconds(1))
        snapshots["afterRelogin"] = ["A": a.snapshot.json, "B": b.snapshot.json]
        check("A's inventory and zeny after a fresh login equal the client's view", a.snapshot == shownA, "login \(a.snapshot), shown \(shownA)")
        check("B's inventory and zeny after a fresh login equal the client's view", b.snapshot == shownB, "login \(b.snapshot), shown \(shownB)")
    }

    // MARK: - Steps

    /// The UI path: tap the player, press the target action button.
    private func requestTrade(from client: Client, to other: Client) throws {
        guard let scene = client.scene else {
            throw ScenarioError("\(client.label) has no map")
        }
        scene.handleInteraction(.mapObject(objectID: other.accountID))
        guard scene.state.selectedPlayer?.accountID == other.accountID else {
            throw ScenarioError("\(client.label) could not select \(other.label): \(String(describing: scene.state.selectedPlayer))")
        }
        scene.performTargetAction()
    }

    private func openTrade(from requester: Client, to target: Client) async throws {
        try requestTrade(from: requester, to: target)
        try await wait("\(target.label) sees the request") { target.playSession?.trade.incomingRequest != nil }
        target.playSession?.answerTradeRequest(accept: true)
        try await wait("both trade windows open") { requester.playSession?.trade.current != nil && target.playSession?.trade.current != nil }
        check("trade window names the partner (\(requester.label) and \(target.label))",
              requester.playSession?.trade.current?.partner.name == target.characterName && target.playSession?.trade.current?.partner.name == requester.characterName
                && requester.playSession?.trade.current?.partner.accountID == target.accountID,
              "\(requester.label) trades with \(requester.playSession?.trade.current?.partner.name ?? "-"), \(target.label) with \(target.playSession?.trade.current?.partner.name ?? "-")")
    }

    private func send(_ client: Client, _ text: String) {
        Log.line("\(client.label): \(text)")
        client.playSession?.sendMessage(text)
    }

    // MARK: - Connecting

    private func connect(_ client: Client) async throws {
        let gameSession = GameSession(resourceManager: resourceManager)
        client.gameSession = gameSession
        gameSession.start(GameSession.Configuration(serverAddress: options.host, serverPort: options.port))
        Log.line("\(client.label): login as \(client.user)")
        gameSession.login(username: client.user, password: client.password)

        try await wait("\(client.label) character select", timeout: options.stageTimeout) {
            if case .login(.characterSelect) = gameSession.stage { return true }
            if let error = gameSession.errorMessages.first {
                Log.line("\(client.label): client error \(error.content)")
            }
            return false
        }
        guard case .login(.characterSelect(let characters)) = gameSession.stage else {
            throw ScenarioError("\(client.label) did not reach character select")
        }

        var character = characters.first { $0.name.caseInsensitiveCompare(client.characterName) == .orderedSame }
        if character == nil {
            Log.line("\(client.label): creating \(client.characterName)")
            character = try await createCharacter(gameSession, name: client.characterName)
        }
        guard let character else {
            throw ScenarioError("\(client.label) has no character")
        }

        gameSession.selectCharacter(slot: character.charNum)
        try await wait("\(client.label) map server", timeout: options.stageTimeout) { gameSession.playSession != nil }
        try await wait("\(client.label) map load", timeout: options.mapLoadTimeout) { gameSession.mapScene != nil }
        Log.line("\(client.label): on \(gameSession.mapScene?.mapName ?? "-") at \(gameSession.mapScene?.player.gridPosition ?? .zero), account \(client.accountID)")
    }

    private func createCharacter(_ gameSession: GameSession, name: String) async throws -> CharacterInfo {
        let used = Set(gameSession.characters.map(\.charNum))
        guard let slot = (0..<max(gameSession.maxCharacterSlots, 1)).first(where: { !used.contains($0) }) else {
            throw ScenarioError("no free character slot")
        }

        var info = CharacterInfo()
        info.name = name
        info.job = 0
        info.head = 2
        info.headPalette = 0
        info.str = 5
        info.agi = 5
        info.vit = 5
        info.int = 5
        info.dex = 5
        info.luk = 5
        info.charNum = slot
        if let account = gameSession.account {
            info.sex = account.sex
        }

        gameSession.makeCharacter(slot: slot)
        gameSession.createCharacter(info)
        let before = gameSession.characters.count
        try await wait("character creation", timeout: 30) { gameSession.characters.count > before }
        guard let created = gameSession.characters.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ScenarioError("character \(name) was not created")
        }
        return created
    }

    // MARK: - Helpers

    struct ScenarioError: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) {
            self.description = description
        }
    }

    private func wait(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ScenarioError("timeout after \(Int(timeout)) s waiting for \(what)")
    }

    private func chebyshev(_ a: SIMD2<Int>?, _ b: SIMD2<Int>?) -> Int {
        guard let a, let b else {
            return Int.max
        }
        return max(abs(a.x - b.x), abs(a.y - b.y))
    }

    private func check(_ name: String, _ passed: Bool, _ detail: String) {
        Log.line("\(passed ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " (\(detail))")")
        checks.append(["name": name, "passed": passed, "detail": detail])
    }

    // MARK: - Report

    private func report(passed: Bool, seconds: TimeInterval) {
        let failed = checks.filter { ($0["passed"] as? Bool) != true }
        print("trade test: \(passed ? "PASS" : "FAIL"), \(checks.count - failed.count)/\(checks.count) checks in \(Int(seconds)) s")
        for entry in failed {
            print("  FAIL \(entry["name"] ?? "?"): \(entry["detail"] ?? "")")
        }

        guard let path = options.jsonPath else {
            return
        }
        let result: [String: Any] = [
            "scenario": "trade",
            "date": ISO8601DateFormatter().string(from: Date()),
            "passed": passed,
            "seconds": Int(seconds),
            "server": "\(options.host):\(options.port)",
            "accounts": [
                ["label": a.label, "user": a.user, "character": a.characterName, "accountID": Int(a.accountID)],
                ["label": b.label, "user": b.user, "character": b.characterName, "accountID": Int(b.accountID)],
            ],
            "checks": checks,
            "snapshots": snapshots,
            "messagesA": Array(a.messages.suffix(30)),
            "messagesB": Array(b.messages.suffix(30)),
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            print("wrote \(path)")
        } catch {
            print("cannot write \(path): \(error)")
        }
    }
}
