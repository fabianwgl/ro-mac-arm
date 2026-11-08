import Foundation
import RagnarokConstants
@testable import RagnarokGame
import RagnarokModels
import RagnarokNetwork
import RagnarokPackets
import RagnarokResources

/// Item appraisal, one probe on one account.
///
/// The probe logs in as a GM account (group 99) and sets itself up with `@` commands. Appraisal: an unidentified
/// Knife (`@item2` with identify flag 0) and Magnifiers. A Magnifier is used through `PlaySession.useItem`, the same
/// call the inventory menu makes. The server answers with `ZC_ITEMIDENTIFY_LIST`, the probe cancels once (the server
/// must leave the menu, which a second Magnifier use proves), then picks the Knife and checks that the inventory flag
/// flips on `ZC_ACK_ITEMIDENTIFY`. The same is done with the Item Appraisal skill of the Merchant. A request for an
/// index nothing is stored at shows that the server ignores it.
@MainActor
final class AppraisalScenario {
    let options: Options
    let resourceManager: ResourceManager

    private var steps: [[String: Any]] = []
    private var checks: [[String: Any]] = []
    private var errors: [String] = []
    private var facts: [String: Any] = [:]
    private let startDate = Date()

    private let knifeID = 1201
    private let magnifierID = 611
    private let itemAppraisalSkillID = 40

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
            try await runAppraisal(gameSession, playSession)
            try await runItemAppraisalSkill(gameSession, playSession)
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

    // MARK: - Appraisal with a Magnifier

    private func runAppraisal(_ gameSession: GameSession, _ playSession: PlaySession) async throws {
        step("get an unidentified Knife and Magnifiers")
        // A rerun finds what the last one left: count from there.
        let magnifiersBefore = inventoryAmount(of: magnifierID, playSession)
        command(playSession, "@item2 \(knifeID) 1 0 0 0 0 0 0 0")
        try await require(timeout: 15, "an unidentified Knife in the inventory") { self.unidentifiedKnife(playSession) != nil }
        command(playSession, "@item \(magnifierID) 5")
        try await require(timeout: 15, "five more Magnifiers") { self.inventoryAmount(of: self.magnifierID, playSession) >= magnifiersBefore + 5 }

        guard let knife = unidentifiedKnife(playSession) else {
            throw ScenarioError("no unidentified Knife")
        }
        let knifeIndex = knife.index
        let itemInfoTable = playSession.context.itemInfoTable
        let unidentifiedName = itemInfoTable.localizedItemName(forItemID: knifeID, isIdentified: false)
        let identifiedName = itemInfoTable.localizedItemName(forItemID: knifeID, isIdentified: true)
        facts["knifeIndex"] = knifeIndex
        facts["knifeNameUnidentified"] = unidentifiedName ?? "nil"
        facts["knifeNameIdentified"] = identifiedName ?? "nil"
        check("unidentified and identified Knife names differ", unidentifiedName != nil && unidentifiedName != identifiedName,
              detail: "\(unidentifiedName ?? "nil") / \(identifiedName ?? "nil")")
        check("the item list flags the Knife as unidentified", knife.isIdentified == false, detail: "index \(knifeIndex)")

        // Use a Magnifier, then leave the picker.
        step("use a Magnifier")
        try await useMagnifier(playSession)
        try await require(timeout: 15, "the appraisal list (ZC_ITEMIDENTIFY_LIST)") { playSession.appraisal.isPickerOpen }
        check("picker offers the Knife", playSession.appraisal.candidateIndices?.contains(knifeIndex) == true,
              detail: "\(playSession.appraisal.candidateIndices ?? [])")
        let offered = playSession.appraisal.candidateIndices ?? []
        let unidentifiedInInventory = Set(playSession.inventory.items.values.filter { !$0.isIdentified }.map(\.index))
        check("picker offers exactly the unidentified items", Set(offered) == unidentifiedInInventory,
              detail: "offered \(offered.sorted()), unidentified \(unidentifiedInInventory.sorted())")
        facts["offeredIndices"] = offered

        step("cancel the picker")
        playSession.cancelAppraisal()
        check("picker closed by cancel", playSession.appraisal.isPickerOpen == false, detail: "")
        try await pause(1)
        check("cancel identified nothing", playSession.inventory.items[knifeIndex]?.isIdentified == false, detail: "")

        // A Magnifier is used up whether the appraisal ends in a pick or a cancel (it is a DelayConsume item).
        // The server only lets an item skill start when the cancel cleared its menu state.
        step("use a Magnifier again after the cancel")
        try await useMagnifier(playSession)
        try await require(timeout: 15, "the appraisal list after a cancel") { playSession.appraisal.isPickerOpen }
        check("the server left the menu on cancel (a second list arrived)", true, detail: "")

        // A request for something the server did not offer is ignored: no answer, the menu is left.
        step("send a request for an index nothing is stored at")
        let answersBefore = playSession.messageCenter.messages.filter { $0.content.contains("ppraised") }.count
        playSession.sendPacket(PacketFactory.CZ_REQ_ITEMIDENTIFY(index: 999))
        try await pause(1.5)
        let answersAfter = playSession.messageCenter.messages.filter { $0.content.contains("ppraised") }.count
        check("server ignores an invalid index without an answer",
              answersAfter == answersBefore && playSession.inventory.items[knifeIndex]?.isIdentified == false,
              detail: "appraisal messages \(answersBefore) -> \(answersAfter)")
        playSession.appraisal.candidateIndices = nil

        step("use a Magnifier and pick the Knife")
        try await useMagnifier(playSession)
        try await require(timeout: 15, "the appraisal list before the pick") { playSession.appraisal.isPickerOpen }
        let magnifiersBeforePick = inventoryAmount(of: magnifierID, playSession)
        playSession.appraiseItem(at: knifeIndex)
        check("picker closed by the pick", playSession.appraisal.isPickerOpen == false, detail: "")
        try await require(timeout: 15, "the Knife to become identified (ZC_ACK_ITEMIDENTIFY)") {
            playSession.inventory.items[knifeIndex]?.isIdentified == true
        }
        check("inventory flag flipped to identified", playSession.inventory.items[knifeIndex]?.isIdentified == true, detail: "index \(knifeIndex)")
        check("the item is still the Knife", playSession.inventory.items[knifeIndex]?.itemID == knifeID,
              detail: "item \(playSession.inventory.items[knifeIndex]?.itemID ?? 0)")
        check("success message", playSession.messageCenter.messages.last?.content.hasPrefix("Appraised: ") == true,
              detail: playSession.messageCenter.messages.last?.content ?? "nil")
        try await pause(1)
        facts["magnifiersBeforePick"] = magnifiersBeforePick
        facts["magnifiersAfterPick"] = inventoryAmount(of: magnifierID, playSession)

        step("a second identify list has nothing left for the Knife")
        // Whatever else is unidentified is offered, the Knife is not.
        try await useMagnifier(playSession)
        let listed = await waitFor(timeout: 5, "an appraisal list") { playSession.appraisal.isPickerOpen }
        if listed {
            check("the identified Knife is not offered again", playSession.appraisal.candidateIndices?.contains(knifeIndex) == false,
                  detail: "\(playSession.appraisal.candidateIndices ?? [])")
            playSession.cancelAppraisal()
        } else {
            check("no list when nothing is unidentified", unidentifiedKnife(playSession) == nil, detail: "")
        }
        try await pause(1)
    }

    // MARK: - Appraisal with the Item Appraisal skill

    private func runItemAppraisalSkill(_ gameSession: GameSession, _ playSession: PlaySession) async throws {
        step("become a Merchant for the Item Appraisal skill")
        command(playSession, "@jobchange 5")
        try await pause(2)
        command(playSession, "@allskill")
        try await pause(1)
        command(playSession, "@heal 9999 9999")
        try await pause(1)
        command(playSession, "@item2 \(knifeID) 1 0 0 0 0 0 0 0")
        try await require(timeout: 15, "a new unidentified Knife") { self.unidentifiedKnife(playSession) != nil }
        guard let knife = unidentifiedKnife(playSession), let scene = gameSession.mapScene else {
            throw ScenarioError("no unidentified Knife or no map")
        }
        let knifeIndex = knife.index
        let magnifiers = inventoryAmount(of: magnifierID, playSession)

        step("use Item Appraisal (skill \(itemAppraisalSkillID))")
        playSession.useSkill(skillID: itemAppraisalSkillID, level: 1, onTarget: scene.player.objectID)
        try await require(timeout: 15, "the appraisal list from the skill") { playSession.appraisal.isPickerOpen }
        check("skill list offers the Knife", playSession.appraisal.candidateIndices?.contains(knifeIndex) == true,
              detail: "\(playSession.appraisal.candidateIndices ?? [])")

        playSession.appraiseItem(at: knifeIndex)
        try await require(timeout: 15, "the Knife to become identified through the skill") {
            playSession.inventory.items[knifeIndex]?.isIdentified == true
        }
        check("inventory flag flipped through the skill", playSession.inventory.items[knifeIndex]?.isIdentified == true, detail: "index \(knifeIndex)")
        try await pause(1)
        check("the skill does not use a Magnifier", inventoryAmount(of: magnifierID, playSession) == magnifiers,
              detail: "Magnifiers \(magnifiers) -> \(inventoryAmount(of: magnifierID, playSession))")
    }

    // MARK: - Login to map

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

    /// The Magnifier through the item-use path of the inventory menu.
    private func useMagnifier(_ playSession: PlaySession) async throws {
        guard let magnifier = playSession.inventory.items.values.first(where: { $0.itemID == magnifierID }) else {
            throw ScenarioError("no Magnifier in the inventory")
        }
        playSession.useItem(at: magnifier.index)
    }

    private func unidentifiedKnife(_ playSession: PlaySession) -> InventoryItem? {
        playSession.inventory.items.values
            .filter { $0.itemID == knifeID && !$0.isIdentified }
            .sorted()
            .first
    }

    private func command(_ playSession: PlaySession, _ text: String) {
        step("chat: \(text)")
        playSession.sendMessage(text)
    }

    private func inventoryAmount(of itemID: Int, _ playSession: PlaySession) -> Int {
        playSession.inventory.items.values.filter { $0.itemID == itemID }.reduce(0) { $0 + $1.amount }
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
        Log.line("[appraisal] \(text)")
        steps.append(["t": (Date().timeIntervalSince(startDate) * 10).rounded() / 10, "step": text])
    }

    private func fail(_ text: String) {
        Log.line("[appraisal] FAILED: \(text)")
        errors.append(text)
    }

    private func check(_ name: String, _ ok: Bool, detail: String) {
        Log.line("[appraisal] check \(ok ? "PASS" : "FAIL"): \(name) \(detail)")
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
            "scenario": "appraisal",
            "user": options.user,
            "character": options.charName,
            "passed": passed,
            "seconds": (Date().timeIntervalSince(startDate) * 10).rounded() / 10,
            "checks": checks,
            "errors": errors,
            "facts": facts,
            "steps": steps,
        ]
        Log.line("[appraisal] result: \(passed ? "PASS" : "FAIL") (\(checks.filter { $0["passed"] as? Bool == true }.count)/\(checks.count) checks)")
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
