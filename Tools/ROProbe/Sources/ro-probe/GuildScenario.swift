import CoreGraphics
import Foundation
import ImageIO
import RagnarokConstants
@testable import RagnarokGame
import RagnarokModels
import RagnarokNetwork
import RagnarokPackets
import RagnarokResources

/// Guild skills and the guild emblem, one probe on one account.
///
/// The probe logs in as a GM account (group 99) and sets itself up with `@` commands. It founds a guild with an
/// Emperium when the character has none, so a rerun continues with the guild of the last run. Skills: the list of
/// `ZC_GUILD_SKILLINFO`, skill points from `@guildlvup`, and level ups through `PlaySession.upgradeGuildSkill`, the
/// call the Skills tab makes, until Battle Orders is learned. Battle Orders is then cast with
/// `PlaySession.useGuildSkill` on a map switched to guild war mode (`@gvgon`), the only place rAthena allows it.
/// Emblem: a generated image goes through `PlaySession.changeGuildEmblem`, the server must hand out a new emblem
/// version with a picture that reads back, and a plain request (`CZ_REQ_GUILD_EMBLEM_IMG`) must return it again.
@MainActor
final class GuildScenario {
    let options: Options
    let resourceManager: ResourceManager

    private var steps: [[String: Any]] = []
    private var checks: [[String: Any]] = []
    private var errors: [String] = []
    private var facts: [String: Any] = [:]
    private let startDate = Date()

    private let emperiumID = 714

    /// The levels Battle Orders needs, in the order they have to be learned (`db/re/guild_skill_tree.yml`).
    private let skillTargets: [(name: String, level: Int)] = [
        ("GD_APPROVAL", 1),
        ("GD_EXTENSION", 2),
        ("GD_BATTLEORDER", 1),
    ]

    init(options: Options, resourceManager: ResourceManager) {
        self.options = options
        self.resourceManager = resourceManager
    }

    // MARK: - Run

    func run() async -> Bool {
        let gameSession = GameSession(resourceManager: resourceManager)
        gameSession.start(GameSession.Configuration(serverAddress: options.host, serverPort: options.port))
        defer {
            gameSession.stop()
        }

        var passed = false
        do {
            let playSession = try await enterMap(gameSession)
            try await ensureGuild(playSession)
            try await runSkills(playSession)
            try await runBattleOrders(playSession)
            try await runEmblem(playSession)
            passed = true
        } catch {
            fail("\(error)")
        }

        if let playSession = gameSession.playSession {
            recordMessages(playSession)
        }
        writeResult(passed: passed && errors.isEmpty)
        return passed && errors.isEmpty
    }

    // MARK: - Guild

    private func ensureGuild(_ playSession: PlaySession) async throws {
        // ZC_UPDATE_GDID arrives right after the map entry when the character has a guild.
        try await pause(2)

        if !playSession.guildState.guild.isInGuild {
            step("get an Emperium and found a guild")
            command(playSession, "@item \(emperiumID) 1")
            try await require(timeout: 15, "an Emperium in the inventory") {
                playSession.inventory.items.values.contains { $0.itemID == self.emperiumID }
            }
            // Guild names are unique on the server, so each probe character founds its own.
            playSession.createGuild(name: "\(options.charName) Guild")
            try await require(timeout: 15, "the new guild (ZC_UPDATE_GDID)") { playSession.guildState.guild.isInGuild }
            facts["guildCreated"] = true
        } else {
            facts["guildCreated"] = false
        }

        let guild = playSession.guildState.guild
        facts["guildID"] = Int(guild.guildID)
        facts["guildName"] = guild.name
        check("the character is the master of its guild", guild.isMaster, detail: "\(guild.name) (\(guild.guildID))")
    }

    // MARK: - Skills

    private func runSkills(_ playSession: PlaySession) async throws {
        step("ask for the guild window data")
        playSession.refreshGuild()
        try await require(timeout: 15, "the guild skill list (ZC_GUILD_SKILLINFO)") { !playSession.guildState.guild.skills.isEmpty }

        let listed = playSession.guildState.guild.skills
        facts["skillsAtStart"] = listed.map { "\($0.name) \($0.level)" }
        facts["skillPointsAtStart"] = playSession.guildState.guild.skillPoints
        check("the list has Official Guild Approval", listed.contains { $0.name == "GD_APPROVAL" }, detail: "\(listed.count) skills")
        check("skills have a display name", listed.allSatisfy { !playSession.guildSkillName($0).isEmpty },
              detail: listed.prefix(3).map { playSession.guildSkillName($0) }.joined(separator: ", "))

        for target in skillTargets {
            while true {
                // The server lists a skill only once the guild meets its requirements.
                try await require(timeout: 15, "\(target.name) in the skill list") {
                    playSession.guildState.guild.skills.contains { $0.name == target.name }
                }
                guard let skill = playSession.guildState.guild.skills.first(where: { $0.name == target.name }),
                      skill.level < target.level else {
                    break
                }
                try await upgrade(skill, playSession)
            }
        }

        let learned = playSession.guildState.guild.skills
        facts["skillsAtEnd"] = learned.map { "\($0.name) \($0.level)" }
        for target in skillTargets {
            let level = learned.first { $0.name == target.name }?.level ?? 0
            check("\(target.name) is at level \(target.level) or above", level >= target.level, detail: "level \(level)")
        }
    }

    /// One level through the Skills tab's call, with a skill point from `@guildlvup` when the guild has none.
    private func upgrade(_ skill: Guild.Skill, _ playSession: PlaySession) async throws {
        if playSession.guildState.guild.skillPoints == 0 {
            step("raise the guild level for a skill point")
            check("no level up is offered without skill points", !playSession.guildState.guild.canUpgrade(skill), detail: skill.name)
            command(playSession, "@guildlvup 1")
            try await require(timeout: 15, "a skill point (ZC_GUILD_SKILLINFO after the level up)") {
                playSession.guildState.guild.skillPoints > 0
            }
        }

        guard let current = playSession.guildState.guild.skill(id: skill.id) else {
            throw ScenarioError("\(skill.name) left the skill list")
        }
        let pointsBefore = playSession.guildState.guild.skillPoints
        let messagesBefore = playSession.messageCenter.messages.count

        step("level up \(current.name) from \(current.level)")
        check("the master may level up \(current.name)", playSession.guildState.guild.canUpgrade(current),
              detail: "points \(pointsBefore), upgradable \(current.isUpgradable)")
        playSession.upgradeGuildSkill(current)
        try await require(timeout: 15, "\(current.name) at level \(current.level + 1)") {
            playSession.guildState.guild.skill(id: current.id)?.level == current.level + 1
        }

        check("the level up cost one skill point", playSession.guildState.guild.skillPoints == pointsBefore - 1,
              detail: "\(pointsBefore) -> \(playSession.guildState.guild.skillPoints)")
        let announced = playSession.messageCenter.messages.dropFirst(messagesBefore).contains { $0.content.hasSuffix("is now level \(current.level + 1).") }
        check("the level up is announced", announced, detail: playSession.guildSkillName(current))
    }

    // MARK: - Battle Orders

    private func runBattleOrders(_ playSession: PlaySession) async throws {
        guard let battleOrders = playSession.guildState.guild.skills.first(where: { $0.name == "GD_BATTLEORDER" }) else {
            throw ScenarioError("Battle Orders is not in the skill list")
        }
        check("Battle Orders is a skill the master can use", battleOrders.isUsable && !battleOrders.isPassive,
              detail: "type \(battleOrders.type), level \(battleOrders.level)")
        let approval = playSession.guildState.guild.skills.first { $0.name == "GD_APPROVAL" }
        check("Official Guild Approval is passive and has no Use button", approval?.isPassive == true && approval?.isUsable == false,
              detail: "type \(approval?.type ?? -1)")

        let statusID = OfficialStatusChangeID.efst_gdskill_battleorder.rawValue
        let wasActive = playSession.statusChanges.contains { $0.statusID == statusID }
        facts["battleOrdersActiveBefore"] = wasActive

        // rAthena refuses the guild's active skills outside guild war maps (skill_check_condition_castbegin).
        step("switch the map to guild war mode and use Battle Orders")
        command(playSession, "@gvgon")
        try await pause(1.5)
        playSession.useGuildSkill(battleOrders)
        let active = await waitFor(timeout: 15, "the Battle Orders status") {
            playSession.statusChanges.contains { $0.statusID == statusID }
        }
        command(playSession, "@gvgoff")
        try await pause(1)

        // The skill has a five minute delay for the whole guild, so a rerun inside it finds the status still on.
        check("Battle Orders put its status on the master", active, detail: wasActive ? "already active from the last run" : "new")
    }

    // MARK: - Emblem

    private func runEmblem(_ playSession: PlaySession) async throws {
        let guildID = playSession.guildState.guild.guildID
        let versionBefore = playSession.guildState.guild.emblemID
        facts["emblemVersionBefore"] = versionBefore

        // A different color each run, so the server never gets the picture it already has.
        let shade = UInt8(64 + Int(Date().timeIntervalSince1970) % 128)
        let color: [UInt8] = [shade, 0x30, 0xd0]
        facts["emblemColor"] = color.map(Int.init)
        let file = try emblemFile(color: color)
        facts["emblemFileBytes"] = file.count

        step("upload an emblem")
        playSession.changeGuildEmblem(fromImageData: file)
        try await require(timeout: 15, "a new emblem version with its picture (ZC_GUILD_EMBLEM_IMG)") {
            let guild = playSession.guildState.guild
            return guild.emblemID > versionBefore && playSession.guildState.emblems[guildID]?.version == UInt32(guild.emblemID)
        }

        let version = playSession.guildState.guild.emblemID
        facts["emblemVersionAfter"] = version
        check("the server counted the emblem version up", version > versionBefore, detail: "\(versionBefore) -> \(version)")
        try checkEmblem(playSession, guildID: guildID, color: color, what: "the emblem the server sent after the upload")

        // What another client does when it meets the guild: ask by guild id.
        step("forget the emblem and ask for it again")
        playSession.guildState.emblems[guildID] = nil
        playSession.guildState.requestedEmblems[guildID] = nil
        playSession.requestGuildEmblemIfNeeded(guildID: guildID, version: version)
        try await require(timeout: 15, "the emblem for a request (CZ_REQ_GUILD_EMBLEM_IMG)") {
            playSession.guildState.emblems[guildID]?.version == UInt32(version)
        }
        try checkEmblem(playSession, guildID: guildID, color: color, what: "the emblem the server sent for a request")
    }

    private func checkEmblem(_ playSession: PlaySession, guildID: UInt32, color: [UInt8], what: String) throws {
        guard let emblem = playSession.guildState.emblems[guildID] else {
            throw ScenarioError("no emblem for guild \(guildID)")
        }
        let image = emblem.image
        check("\(what) is 24 by 24", image.width == 24 && image.height == 24, detail: "\(image.width) x \(image.height)")

        let center = pixel(of: image, row: 12, column: 12)
        let corner = pixel(of: image, row: 1, column: 22)
        // Scaling and the color conversions on the way may move a channel by a step.
        let isUploadedColor = zip(center, color).allSatisfy { abs(Int($0) - Int($1)) <= 2 } && center[3] == 0xff
        check("\(what) has the uploaded color in the middle", isUploadedColor, detail: "\(center), uploaded \(color)")
        check("\(what) is transparent where the upload was", corner[3] == 0, detail: "\(corner)")
    }

    /// A PNG of 96 by 96: one color, with the top right quarter left transparent.
    private func emblemFile(color: [UInt8]) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: 96,
            height: 96,
            bitsPerComponent: 8,
            bytesPerRow: 96 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScenarioError("no bitmap context")
        }
        context.setFillColor(red: CGFloat(color[0]) / 255, green: CGFloat(color[1]) / 255, blue: CGFloat(color[2]) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        // Core Graphics counts rows from the bottom.
        context.clear(CGRect(x: 48, y: 48, width: 48, height: 48))

        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw ScenarioError("no PNG writer")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScenarioError("the PNG was not written")
        }
        return data as Data
    }

    /// The pixel of an image as red, green, blue, alpha. Row 0 is the top row.
    private func pixel(of image: CGImage, row: Int, column: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (row * image.width + column) * 4
        return Array(pixels[offset..<offset + 4])
    }

    // MARK: - Session setup

    private func enterMap(_ gameSession: GameSession) async throws -> PlaySession {
        step("login as \(options.user)")
        gameSession.login(username: options.user, password: options.pass)

        guard await waitFor(timeout: options.stageTimeout, "character select", {
            if case .login(.characterSelect) = gameSession.stage { return true }
            return !gameSession.errorMessages.isEmpty
        }), case .login(.characterSelect(let characters)) = gameSession.stage else {
            throw ScenarioError("login did not reach character select: \(gameSession.errorMessages.first?.content ?? "timeout")")
        }

        var character = characters.first { $0.name.caseInsensitiveCompare(options.charName) == .orderedSame }
        if character == nil {
            step("create character \(options.charName)")
            character = try await createCharacter(gameSession, name: options.charName)
        }
        guard let character else {
            throw ScenarioError("no character")
        }

        step("select character slot \(character.charNum)")
        gameSession.selectCharacter(slot: character.charNum)

        guard await waitFor(timeout: options.stageTimeout, "play stage", { gameSession.playSession != nil }),
              let playSession = gameSession.playSession else {
            throw ScenarioError("map server was not entered")
        }

        guard await waitFor(timeout: options.mapLoadTimeout, "map load", { gameSession.mapScene != nil }) else {
            throw ScenarioError("map did not load")
        }
        step("on map \(gameSession.mapScene?.mapName ?? "?")")
        return playSession
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
        guard await waitFor(timeout: 30, "character creation", {
            gameSession.characters.count > before || !gameSession.errorMessages.isEmpty
        }), let created = gameSession.characters.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ScenarioError("character creation failed")
        }
        return created
    }

    // MARK: - Helpers

    private func command(_ playSession: PlaySession, _ text: String) {
        step("chat: \(text)")
        playSession.sendMessage(text)
    }

    private func pause(_ seconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func require(timeout: TimeInterval, _ what: String, _ condition: @escaping () -> Bool) async throws {
        guard await waitFor(timeout: timeout, what, condition) else {
            throw ScenarioError("timeout after \(Int(timeout)) s waiting for \(what)")
        }
    }

    private func waitFor(timeout: TimeInterval, _ what: String, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    // MARK: - Report

    private func step(_ text: String) {
        Log.line("[guild] \(text)")
        steps.append(["t": (Date().timeIntervalSince(startDate) * 10).rounded() / 10, "step": text])
    }

    private func fail(_ text: String) {
        Log.line("[guild] FAILED: \(text)")
        errors.append(text)
    }

    private func check(_ name: String, _ ok: Bool, detail: String) {
        Log.line("[guild] check \(ok ? "PASS" : "FAIL"): \(name) \(detail)")
        checks.append(["name": name, "passed": ok, "detail": detail])
        if !ok {
            errors.append("check failed: \(name) (\(detail))")
        }
    }

    private func recordMessages(_ playSession: PlaySession) {
        facts["chatMessages"] = playSession.messageCenter.messages.suffix(40).map(\.content)
    }

    private func writeResult(passed: Bool) {
        let result: [String: Any] = [
            "scenario": "guild",
            "user": options.user,
            "character": options.charName,
            "passed": passed,
            "seconds": (Date().timeIntervalSince(startDate) * 10).rounded() / 10,
            "checks": checks,
            "errors": errors,
            "facts": facts,
            "steps": steps,
        ]
        Log.line("[guild] result: \(passed ? "PASS" : "FAIL") (\(checks.filter { $0["passed"] as? Bool == true }.count)/\(checks.count) checks)")
        guard let path = options.jsonPath,
              let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path))
    }

    struct ScenarioError: Error, CustomStringConvertible {
        var description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
