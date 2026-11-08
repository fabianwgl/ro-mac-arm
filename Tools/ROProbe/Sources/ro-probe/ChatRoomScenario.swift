import Foundation
import RagnarokConstants
@testable import RagnarokGame
import RagnarokModels
import RagnarokPackets
import RagnarokResources
import simd

/// Two real clients in one process use a chat room on a live rAthena (`--chatroom-test`).
///
/// `room1` is an administrator (group 99): `@warp`, `@skpoint` and `@recall` set the scene up. `room2` is a plain
/// player (group 0) on purpose: the administrator group has the `join_chat` and `kick_chat` permissions
/// (conf/groups.yml, Law Enforcement), which let it into a private room without the password and make it immune to
/// expel, so an administrator could not show the password and expel paths. `@recall RoomTwo` brings it to the field.
/// Both drive the same `PlaySession` and `MapScene` entry points the UI uses: the create window's OK, a click on the
/// owner, the room window's line, settings, expel, give-the-room and leave.
///
/// Round 1 is the basic flow: create, join, a line each way, the owner renames the room, the member leaves, and the
/// lines that only members get stop reaching the one who left. Round 2 is a private room: wrong password, right
/// password, expel, and the refusal of an expelled member. Round 3 gives the room away and closes it from the new owner.
///
/// The packet tap is not used: two clients would share its counters. Results go to stdout and `--json`.
@MainActor
final class ChatRoomScenario {
    static let basicSkillID = 1
    static let roomMap = "prt_fild08"

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

        var room: ChatRoom? {
            playSession?.chatRoom.current
        }

        var messages: [String] {
            playSession?.messageCenter.messages.map(\.content) ?? lastMessages
        }

        /// What the room window shows as said lines.
        var said: [String] {
            room?.lines.compactMap { line in
                if case .said(let sender) = line.kind {
                    return "\(sender) : \(line.text)"
                }
                return nil
            } ?? []
        }
    }

    let options: Options
    let resourceManager: ResourceManager
    let a: Client
    let b: Client

    private var checks: [[String: Any]] = []
    private var notes: [String] = []
    private var pumping = true

    init(options: Options, resourceManager: ResourceManager) {
        self.options = options
        self.resourceManager = resourceManager
        self.a = Client(label: "A", user: "room1", password: "room1", characterName: "RoomOne")
        self.b = Client(label: "B", user: "room2", password: "room2", characterName: "RoomTwo")
    }

    // MARK: - Entry point

    static func run(options: Options) async -> Bool {
        let clientURL = URL(fileURLWithPath: options.clientDir, isDirectory: true)
        guard FileManager.default.fileExists(atPath: clientURL.appending(path: "data.grf").path(percentEncoded: false)) else {
            Log.line("data.grf not found in \(options.clientDir)")
            return false
        }
        let provider = ClientFilesProvider(url: clientURL, allowAudio: false)
        let scenario = ChatRoomScenario(options: options, resourceManager: ResourceManager(resourceProvider: provider))
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
            Log.line("chat room test aborted: \(error)")
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
        notes.append("room1 is group 99 (administrator), room2 is group 0 (player): groups.yml gives the administrator group join_chat (password bypass) and kick_chat (expel immunity)")
        Log.line("chat room test: connecting \(a.user)/\(a.characterName) and \(b.user)/\(b.characterName)")
        try await connect(a)
        try await connect(b)

        try await meetOnTheField()
        try await giveBasicSkill()

        try await basicRound()
        try await privateRound()
        try await giveAwayRound()
    }

    /// Both characters stand on one cell of one field, which has no NPC for the server's "no NPC near" rule.
    private func meetOnTheField() async throws {
        if a.scene?.mapName.hasPrefix(Self.roomMap) != true {
            send(a, "@warp \(Self.roomMap)")
            try await wait("A on \(Self.roomMap)") { self.a.scene?.mapName.hasPrefix(Self.roomMap) == true }
            try await Task.sleep(for: .seconds(2))
        }
        guard let place = a.scene?.player.gridPosition else {
            throw ScenarioError("A has no position")
        }
        if !isOnFieldNear(place) {
            send(a, "@recall \(b.characterName)")
            try await wait("B next to A") { self.isOnFieldNear(place) }
            try await Task.sleep(for: .seconds(2))
        }
        try await wait("A sees B and B sees A", timeout: 60) {
            self.a.scene?.objects[self.b.accountID] != nil && self.b.scene?.objects[self.a.accountID] != nil
        }
        let distance = chebyshev(a.scene?.player.gridPosition, b.scene?.player.gridPosition)
        check("both players stand within 2 cells", distance <= 2, "A \(a.scene?.player.gridPosition ?? .zero), B \(b.scene?.player.gridPosition ?? .zero), distance \(distance)")
    }

    private func isOnFieldNear(_ place: SIMD2<Int>) -> Bool {
        b.scene?.mapName.hasPrefix(Self.roomMap) == true && chebyshev(b.scene?.player.gridPosition, place) <= 2
    }

    /// rAthena wants Basic Skill level 4 to open a room (`basic_skill_check`). A skill point from `@skpoint` and the same
    /// upgrade request the skill window sends give it, one level at a time. Only A opens rooms.
    private func giveBasicSkill() async throws {
        let wanted = PlaySession.chatRoomBasicSkillLevel
        for client in [a] {
            while (client.playSession?.skillList.skills[Self.basicSkillID]?.level ?? 0) < wanted {
                let level = client.playSession?.skillList.skills[Self.basicSkillID]?.level ?? 0
                if (client.playSession?.playerStatus.skillPoint ?? 0) < 1 {
                    send(client, "@skpoint 1")
                    try await wait("\(client.label) skill point") { (client.playSession?.playerStatus.skillPoint ?? 0) >= 1 }
                }
                client.playSession?.upgradeSkillLevel(skillID: Self.basicSkillID)
                try await wait("\(client.label) Basic Skill level \(level + 1)") {
                    (client.playSession?.skillList.skills[Self.basicSkillID]?.level ?? 0) > level
                }
            }
        }
        check("A has Basic Skill level \(wanted)", (a.playSession?.skillList.skills[Self.basicSkillID]?.level ?? 0) >= wanted,
              "A \(a.playSession?.skillList.skills[Self.basicSkillID]?.level ?? 0)")
    }

    // MARK: - Round 1

    /// Create, join, talk, rename, leave, close.
    private func basicRound() async throws {
        Log.line("round 1: public room")
        let title = "Probe room"

        // The create window: /chat opens it with the title filled in, OK sends it.
        send(a, "/chat \(title)")
        try await wait("A's create window") { self.a.playSession?.chatRoom.createDraft != nil }
        check("/chat opens the create window with the title", a.playSession?.chatRoom.createDraft?.title == title, "\(a.playSession?.chatRoom.createDraft?.title ?? "-")")
        guard var draft = a.playSession?.chatRoom.createDraft else {
            throw ScenarioError("no create draft")
        }
        draft.setLimit(4)
        a.playSession?.createChatRoom(draft)
        try await wait("A in a room") { self.a.room != nil }
        check("A owns the new room alone", a.room?.isOwner == true && a.room?.members.map(\.name) == [a.characterName] && a.room?.title == title,
              "\(String(describing: a.room?.members)) title \(a.room?.title ?? "-")")

        // Others get the sign, the creator draws his own.
        try await wait("B sees A's sign") { self.b.playSession?.chatRoom.sign(ofOwner: self.a.accountID) != nil }
        let sign = b.playSession?.chatRoom.sign(ofOwner: a.accountID)
        check("B's sign has the title, limit 4, one user, public", sign?.title == title && sign?.limit == 4 && sign?.users == 1 && sign?.access == .publicRoom,
              "\(String(describing: sign))")
        check("B can click the owner", b.playSession?.hasChatRoomSign(ownerID: a.accountID) == true, "")
        let ownSigns = a.playSession?.chatRoom.displayedSigns(selfAccountID: a.accountID) { _ in nil } ?? []
        check("A draws his own sign over himself", ownSigns.contains { $0.ownerID == a.accountID && $0.title == title }, "\(ownSigns)")
        let chatID = sign?.chatID ?? 0

        // B clicks A the way the map does.
        try click(from: b, on: a)
        try await wait("B in the room") { self.b.room != nil }
        try await wait("A sees B enter") { self.a.room?.members.count == 2 }
        check("B joined a room owned by A", b.room?.members.map(\.name) == [a.characterName, b.characterName] && b.room?.owner?.name == a.characterName && b.room?.isOwner == false
              && b.room?.title == title && b.room?.chatID == chatID,
              "\(String(describing: b.room?.members)) chat \(String(describing: b.room?.chatID)) expected \(chatID)")
        check("A sees B as a normal member", a.room?.members.map(\.name) == [a.characterName, b.characterName] && a.room?.isOwner == true, "\(String(describing: a.room?.members))")

        // A line each way, only members get them.
        let lineA = "hello from the owner"
        let lineB = "hello from the member"
        a.playSession?.sayInChatRoom(lineA)
        try await wait("B gets A's line") { self.b.said.contains("\(self.a.characterName) : \(lineA)") }
        b.playSession?.sayInChatRoom(lineB)
        try await wait("A gets B's line") { self.a.said.contains("\(self.b.characterName) : \(lineB)") }
        check("each side sees both lines in the room window", a.said == ["\(a.characterName) : \(lineA)", "\(b.characterName) : \(lineB)"] && b.said == a.said,
              "A \(a.said), B \(b.said)")
        check("the chat box got the lines too", a.messages.contains("\(b.characterName) : \(lineB)") && b.messages.contains("\(a.characterName) : \(lineA)"), "")

        // The owner renames the room, the member sees it.
        a.playSession?.openChatRoomSettings()
        guard var settings = a.playSession?.chatRoom.settingsDraft else {
            throw ScenarioError("no settings draft")
        }
        check("settings start from the current room", settings.title == title && settings.limit == 4 && settings.isPublic, "\(settings)")
        settings.setTitle("Renamed room")
        a.playSession?.changeChatRoom(settings)
        try await wait("B sees the new title") { self.b.room?.title == "Renamed room" }
        check("owner and member both have the new title", a.room?.title == "Renamed room" && b.room?.title == "Renamed room", "A \(a.room?.title ?? "-"), B \(b.room?.title ?? "-")")
        check("the owner learned the chat id from the change", a.room?.chatID == chatID, "\(String(describing: a.room?.chatID)) expected \(chatID)")
        check("the member draws the new title over the owner", (b.playSession?.chatRoom.displayedSigns(selfAccountID: b.accountID) { _ in nil } ?? []).contains { $0.ownerID == a.accountID && $0.title == "Renamed room" }, "")

        // B leaves.
        b.playSession?.leaveChatRoom()
        try await wait("A sees B leave") { self.a.room?.members.count == 1 }
        check("B is out of the room, A is alone in it", b.room == nil && a.room?.members.map(\.name) == [a.characterName], "")
        try await wait("B gets the refreshed sign") { self.b.playSession?.chatRoom.sign(ofOwner: self.a.accountID)?.title == "Renamed room" }
        check("B's sign shows the new title and one user", b.playSession?.chatRoom.sign(ofOwner: self.a.accountID)?.users == 1, "\(String(describing: b.playSession?.chatRoom.sign(ofOwner: a.accountID)))")

        // Lines that only members get: B is outside now, A inside.
        let before = (a.messages.count, b.messages.count)
        let inside = "only the room hears this"
        let outside = "only the street hears this"
        a.playSession?.sayInChatRoom(inside)
        send(b, outside)
        try await Task.sleep(for: .seconds(3))
        check("a line from inside the room does not reach someone outside", !b.messages.contains { $0.contains(inside) }, "B messages \(b.messages.suffix(3))")
        check("a line from outside does not reach the room", !a.messages.contains { $0.contains(outside) }, "A messages \(a.messages.suffix(3))")
        check("each speaker still sees his own line", a.messages.contains { $0.contains(inside) } && b.messages.contains { $0.contains(outside) },
              "A \(a.messages.count - before.0) new, B \(b.messages.count - before.1) new")

        // A closes the room.
        a.playSession?.leaveChatRoom()
        try await wait("B's sign is gone") { self.b.playSession?.chatRoom.signs.isEmpty == true }
        check("closing the last member's room removes its sign", a.room == nil && b.playSession?.chatRoom.signs.isEmpty == true, "")
    }

    // MARK: - Round 2

    /// Private room: wrong password, right password, expel.
    private func privateRound() async throws {
        Log.line("round 2: private room")
        let title = "Private probe"
        a.playSession?.createChatRoom(ChatRoomSettings(title: title, limit: 3, isPublic: false, password: "pw1234"))
        try await wait("A in the private room") { self.a.room != nil }
        try await wait("B sees the private sign") { self.b.playSession?.chatRoom.sign(ofOwner: self.a.accountID) != nil }
        let sign = b.playSession?.chatRoom.sign(ofOwner: a.accountID)
        check("the sign says private", sign?.access == .privateRoom && sign?.needsPassword == true, "\(String(describing: sign))")

        // The click asks for the password.
        try click(from: b, on: a)
        check("a click on a private room asks for the password", b.playSession?.chatRoom.passwordPrompt?.title == title && b.room == nil, "")

        // Wrong password.
        let refusals = b.messages.count
        if let prompt = b.playSession?.chatRoom.passwordPrompt {
            b.playSession?.joinChatRoom(prompt, password: "nope")
        }
        try await wait("B hears the wrong password or is let in") {
            self.b.messages.dropFirst(refusals).contains("The password is wrong.") || self.b.room != nil
        }
        check("a wrong password lets nobody in", b.room == nil && a.room?.members.count == 1,
              "B in the room: \(b.room != nil). room2 must be a plain player (group 0), the administrator group skips passwords")
        if b.room != nil {
            throw ScenarioError("room2 got into the private room with a wrong password, it is an administrator")
        }

        // Right password.
        try click(from: b, on: a)
        if let prompt = b.playSession?.chatRoom.passwordPrompt {
            b.playSession?.joinChatRoom(prompt, password: "pw1234")
        }
        try await wait("B in the private room") { self.b.room != nil }
        try await wait("A sees B") { self.a.room?.members.count == 2 }
        check("the right password lets B in", b.room?.access == .privateRoom && b.room?.title == title, "")

        // Expel.
        a.playSession?.expelFromChatRoom(name: b.characterName)
        try await wait("B is expelled") { self.b.room == nil }
        try await wait("A sees B go") { self.a.room?.members.count == 1 }
        check("B hears that he was expelled", b.messages.contains("You were expelled from the chat room."), "")
        check("A's list no longer has B", a.room?.members.map(\.name) == [a.characterName], "")

        // The expelled cannot come back.
        try await wait("B sees the refreshed sign") { self.b.playSession?.chatRoom.sign(ofOwner: self.a.accountID) != nil }
        try click(from: b, on: a)
        if let prompt = b.playSession?.chatRoom.passwordPrompt {
            b.playSession?.joinChatRoom(prompt, password: "pw1234")
        }
        try await wait("B hears the refusal") { self.b.messages.last == "You were expelled from that chat room." }
        check("an expelled member is refused even with the password", b.room == nil, "")

        a.playSession?.leaveChatRoom()
        try await wait("the private sign is gone") { self.b.playSession?.chatRoom.signs.isEmpty == true }
    }

    // MARK: - Round 3

    /// The owner gives the room away and leaves, the new owner closes it.
    private func giveAwayRound() async throws {
        Log.line("round 3: give the room away")
        a.playSession?.createChatRoom(ChatRoomSettings(title: "Handover", limit: 5))
        try await wait("A in the room") { self.a.room != nil }
        try await wait("B sees the sign") { self.b.playSession?.chatRoom.sign(ofOwner: self.a.accountID) != nil }
        try click(from: b, on: a)
        try await wait("both in the room") { self.b.room != nil && self.a.room?.members.count == 2 }

        a.playSession?.giveChatRoom(to: b.characterName)
        try await wait("B is the owner") { self.b.room?.isOwner == true && self.a.room?.isOwner == false }
        check("A gave the room to B and both lists agree", a.room?.owner?.name == b.characterName && b.room?.owner?.name == b.characterName
              && a.room?.members.first?.name == b.characterName && b.room?.members.first?.name == b.characterName,
              "A \(String(describing: a.room?.members)), B \(String(describing: b.room?.members))")
        check("B can open the settings now, A cannot", { () -> Bool in
            self.b.playSession?.openChatRoomSettings()
            self.a.playSession?.openChatRoomSettings()
            return self.b.playSession?.chatRoom.settingsDraft != nil && self.a.playSession?.chatRoom.settingsDraft == nil
        }(), "")
        b.playSession?.cancelChatRoomSettings()

        // The old owner leaves, the new owner stays with the room.
        a.playSession?.leaveChatRoom()
        try await wait("B alone") { self.b.room?.members.count == 1 }
        check("B keeps the room after A left", b.room?.isOwner == true && b.room?.members.map(\.name) == [b.characterName], "")
        try await wait("A sees B's sign") { self.a.playSession?.chatRoom.sign(ofOwner: self.b.accountID) != nil }
        check("A sees the sign over B, the new owner", a.playSession?.chatRoom.sign(ofOwner: b.accountID)?.title == "Handover", "")

        b.playSession?.leaveChatRoom()
        try await wait("the sign is gone") { self.a.playSession?.chatRoom.signs.isEmpty == true }
        check("the last member closes the room", b.room == nil && a.playSession?.chatRoom.signs.isEmpty == true, "")
    }

    // MARK: - Steps

    /// The UI path: tap the owner on the map.
    private func click(from client: Client, on owner: Client) throws {
        guard let scene = client.scene else {
            throw ScenarioError("\(client.label) has no map")
        }
        scene.handleInteraction(.mapObject(objectID: owner.accountID))
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
        print("chat room test: \(passed ? "PASS" : "FAIL"), \(checks.count - failed.count)/\(checks.count) checks in \(Int(seconds)) s")
        for entry in failed {
            print("  FAIL \(entry["name"] ?? "?"): \(entry["detail"] ?? "")")
        }

        guard let path = options.jsonPath else {
            return
        }
        let result: [String: Any] = [
            "scenario": "chatroom",
            "date": ISO8601DateFormatter().string(from: Date()),
            "passed": passed,
            "seconds": Int(seconds),
            "server": "\(options.host):\(options.port)",
            "accounts": [
                ["label": a.label, "user": a.user, "character": a.characterName, "accountID": Int(a.accountID)],
                ["label": b.label, "user": b.user, "character": b.characterName, "accountID": Int(b.accountID)],
            ],
            "checks": checks,
            "notes": notes,
            "messagesA": Array(a.messages.suffix(40)),
            "messagesB": Array(b.messages.suffix(40)),
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
