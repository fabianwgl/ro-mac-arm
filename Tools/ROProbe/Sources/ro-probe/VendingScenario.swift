import Foundation
import RagnarokConstants
@testable import RagnarokGame
import RagnarokModels
import RagnarokPackets
import RagnarokResources
import simd

/// Two probes trade through a vending shop: `--vending seller` opens a shop, `--vending buyer` buys from it.
///
/// Both log in as GM accounts (group 99), set themselves up with `@` commands and warp to the same cell.
/// The seller becomes a Merchant with a cart, moves potions into it and uses the Vending skill through the same
/// `PlaySession` calls the shop windows make. The buyer waits for the sign, clicks the vendor the way the map does
/// and buys. Each probe checks its own inventory, cart and zeny against what the trade should have changed and
/// writes the result to `--json`.
@MainActor
final class VendingScenario {
    enum Role: String {
        case seller
        case buyer
    }

    let options: Options
    let role: Role
    let resourceManager: ResourceManager

    private var steps: [[String: Any]] = []
    private var checks: [[String: Any]] = []
    private var errors: [String] = []
    private var facts: [String: Any] = [:]
    private let startDate = Date()

    // The trade: potions at a fixed price, so the zeny of both sides can be predicted.
    private let potionID = 501
    private let potionPrice = 100
    private let stockInCart = 40
    private let amountForSale = 30
    private let amountToBuy = 10

    init(options: Options, role: Role, resourceManager: ResourceManager) {
        self.options = options
        self.role = role
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
            switch role {
            case .seller:
                passed = try await runSeller(gameSession, playSession)
            case .buyer:
                passed = try await runBuyer(gameSession, playSession)
            }
        } catch {
            fail("\(error)")
        }

        if let playSession = gameSession.playSession {
            recordMessages(playSession)
        }
        writeResult(passed: passed && errors.isEmpty)
        return passed && errors.isEmpty
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

    // MARK: - Seller

    private func runSeller(_ gameSession: GameSession, _ playSession: PlaySession) async throws -> Bool {
        step("become a Merchant with a cart and potions")
        command(playSession, "@jobchange 5")
        try await pause(2)
        command(playSession, "@allskill")
        try await pause(1)
        command(playSession, "@cart 1")
        try await require(timeout: 15, "a cart") { playSession.vending.cart.maxWeight > 0 }
        // A rerun finds the potions of the last one: count from what is there.
        let inventoryStart = inventoryAmount(of: potionID, playSession)
        let cartStart = cartAmount(of: potionID, playSession)
        command(playSession, "@item \(potionID) \(stockInCart)")
        try await require(timeout: 15, "\(stockInCart) more potions in the inventory") { self.inventoryAmount(of: self.potionID, playSession) >= inventoryStart + self.stockInCart }

        let inventoryIndex = playSession.inventory.items.values.first { $0.itemID == potionID }?.index ?? -1
        playSession.moveItemToCart(index: inventoryIndex, amount: stockInCart)
        try await require(timeout: 15, "potions in the cart") { self.cartAmount(of: self.potionID, playSession) == cartStart + self.stockInCart }
        let cartStock = cartAmount(of: potionID, playSession)

        // Casting Vending takes SP, which a new Merchant lacks.
        command(playSession, "@blvl 60")
        try await pause(1)
        command(playSession, "@heal 9999 9999")
        try await pause(1)

        try await moveToShopCell(gameSession)
        guard let scene = gameSession.mapScene else {
            throw ScenarioError("no map scene")
        }
        facts["sellerPosition"] = "\(scene.mapName) \(scene.player.gridPosition.x),\(scene.player.gridPosition.y)"

        let zenyBefore = playSession.playerStatus.zeny
        facts["sellerZenyBefore"] = zenyBefore
        facts["sellerCartBefore"] = cartStock
        facts["sellerInventoryBefore"] = inventoryAmount(of: potionID, playSession)

        step("use Vending (skill 41)")
        playSession.useSkill(skillID: 41, level: 10, onTarget: scene.player.objectID)
        try await require(timeout: 15, "the shop set up window (ZC_OPENSTORE)") { playSession.vending.setup != nil }
        facts["setupSlots"] = playSession.vending.setup?.slots ?? 0

        guard let cartIndex = playSession.vending.cart.items.values.first(where: { $0.itemID == potionID })?.index else {
            throw ScenarioError("potions are not in the cart")
        }
        playSession.setVendingTitle(options.vendingTitle)
        playSession.setVendingAmount(amountForSale, forCartIndex: cartIndex)
        playSession.setVendingPrice(potionPrice, forCartIndex: cartIndex)
        playSession.openVendingShop()
        try await require(timeout: 15, "the shop to open (ZC_PC_PURCHASE_MYITEMLIST, ZC_ACK_OPENSTORE2)") {
            playSession.vending.ownShop != nil && playSession.vending.setup == nil
        }
        check("shop is open with the stock", playSession.vending.ownShop?.item(at: cartIndex)?.amount == amountForSale,
              detail: "own shop item \(String(describing: playSession.vending.ownShop?.item(at: cartIndex)))")
        check("own sign is set", playSession.vending.signs[playSession.account.accountID] == options.vendingTitle,
              detail: "\(playSession.vending.signs)")
        step("shop open, waiting for a buyer (up to \(Int(options.vendingTimeout)) s)")

        let sold = await waitFor(timeout: options.vendingTimeout, "a sale", {
            self.tick(gameSession)
            return (playSession.vending.ownShop?.item(at: cartIndex)?.sold ?? 0) >= self.amountToBuy
        })
        guard sold else {
            throw ScenarioError("nothing was bought within \(Int(options.vendingTimeout)) s")
        }
        step("sold \(amountToBuy), checking")
        // The zeny and cart updates follow the sold notice.
        try await pause(2)

        let earned = amountToBuy * potionPrice
        check("seller zeny rose by the price", playSession.playerStatus.zeny == zenyBefore + earned,
              detail: "zeny \(zenyBefore) -> \(playSession.playerStatus.zeny), expected +\(earned)")
        check("seller cart lost the potions", cartAmount(of: potionID, playSession) == cartStock - amountToBuy,
              detail: "cart \(cartStock) -> \(cartAmount(of: potionID, playSession))")
        check("own shop counts the sale", playSession.vending.ownShop?.earnedZeny == earned,
              detail: "earned \(String(describing: playSession.vending.ownShop?.earnedZeny))")
        check("seller inventory unchanged", inventoryAmount(of: potionID, playSession) == facts["sellerInventoryBefore"] as? Int,
              detail: "inventory potions \(inventoryAmount(of: potionID, playSession))")
        facts["sellerZenyAfter"] = playSession.playerStatus.zeny
        facts["sellerCartAfter"] = cartAmount(of: potionID, playSession)

        step("close the shop")
        playSession.closeOwnVendingShop()
        try await pause(1)
        check("shop closed", playSession.vending.ownShop == nil, detail: "")
        return true
    }

    // MARK: - Buyer

    private func runBuyer(_ gameSession: GameSession, _ playSession: PlaySession) async throws -> Bool {
        step("prepare zeny")
        command(playSession, "@zeny 100000")
        try await require(timeout: 15, "zeny") { playSession.playerStatus.zeny >= 100_000 }

        try await moveToShopCell(gameSession)
        guard let scene = gameSession.mapScene else {
            throw ScenarioError("no map scene")
        }
        facts["buyerPosition"] = "\(scene.mapName) \(scene.player.gridPosition.x),\(scene.player.gridPosition.y)"

        step("wait for a shop sign (up to \(Int(options.vendingTimeout)) s)")
        let seen = await waitFor(timeout: options.vendingTimeout, "a shop sign", {
            self.tick(gameSession)
            return playSession.vending.signs.contains { scene.objects[$0.key] != nil }
        })
        guard seen, let (vendorID, title) = playSession.vending.signs.first(where: { scene.objects[$0.key] != nil }) else {
            throw ScenarioError("no shop sign appeared")
        }
        facts["vendorID"] = Int(vendorID)
        facts["signTitle"] = title
        check("sign shows the title", title == options.vendingTitle, detail: title)
        step("sign \"\(title)\" over player \(vendorID)")

        let zenyBefore = playSession.playerStatus.zeny
        let potionsBefore = inventoryAmount(of: potionID, playSession)
        facts["buyerZenyBefore"] = zenyBefore
        facts["buyerPotionsBefore"] = potionsBefore

        // The click on the vendor, as the map scene handles it.
        step("click the vendor")
        scene.handleInteraction(.mapObject(objectID: vendorID))
        try await require(timeout: 15, "the shop item list (ZC_PC_PURCHASE_ITEMLIST_FROMMC)") { playSession.vending.shop != nil }
        guard let shop = playSession.vending.shop, let item = shop.items.first(where: { $0.itemID == potionID }) else {
            throw ScenarioError("the shop does not sell potions: \(String(describing: playSession.vending.shop))")
        }
        facts["shopItems"] = shop.items.map { ["index": $0.index, "itemID": $0.itemID, "price": $0.price, "amount": $0.amount] }
        check("shop lists the potions at the price", item.price == potionPrice && item.amount == amountForSale,
              detail: "price \(item.price), amount \(item.amount)")
        check("shop has the vendor title", shop.title == options.vendingTitle, detail: shop.title)

        playSession.setVendingQuantity(amountToBuy, of: item.index)
        check("total is the price of the pick", playSession.vending.shop?.totalPrice == amountToBuy * potionPrice,
              detail: "total \(String(describing: playSession.vending.shop?.totalPrice))")
        step("buy \(amountToBuy)")
        playSession.purchaseFromVendingShop()
        check("window closed after the purchase", playSession.vending.shop == nil, detail: "")

        try await require(timeout: 15, "the potions in the inventory") { self.inventoryAmount(of: self.potionID, playSession) == potionsBefore + self.amountToBuy }
        try await pause(2)

        let paid = amountToBuy * potionPrice
        check("buyer got the potions", inventoryAmount(of: potionID, playSession) == potionsBefore + amountToBuy,
              detail: "potions \(potionsBefore) -> \(inventoryAmount(of: potionID, playSession))")
        check("buyer paid the price", playSession.playerStatus.zeny == zenyBefore - paid,
              detail: "zeny \(zenyBefore) -> \(playSession.playerStatus.zeny), expected -\(paid)")
        facts["buyerZenyAfter"] = playSession.playerStatus.zeny
        facts["buyerPotionsAfter"] = inventoryAmount(of: potionID, playSession)
        return true
    }

    // MARK: - Shared steps

    /// Both probes go to the same cell so the sign is in view and the purchase is within reach.
    private func moveToShopCell(_ gameSession: GameSession) async throws {
        step("warp to \(options.vendingMap) \(options.vendingX),\(options.vendingY)")
        guard let playSession = gameSession.playSession else {
            throw ScenarioError("no play session")
        }
        command(playSession, "@warp \(options.vendingMap) \(options.vendingX) \(options.vendingY)")
        try await require(timeout: options.mapLoadTimeout, "the map \(options.vendingMap)") {
            self.tick(gameSession)
            return gameSession.mapScene?.mapName.hasPrefix(self.options.vendingMap) == true
        }
        // Let the objects around spawn.
        try await pause(3)
        tick(gameSession)
    }

    private func command(_ playSession: PlaySession, _ text: String) {
        step("chat: \(text)")
        playSession.sendMessage(text)
    }

    private func inventoryAmount(of itemID: Int, _ playSession: PlaySession) -> Int {
        playSession.inventory.items.values.filter { $0.itemID == itemID }.reduce(0) { $0 + $1.amount }
    }

    private func cartAmount(of itemID: Int, _ playSession: PlaySession) -> Int {
        playSession.vending.cart.items.values.filter { $0.itemID == itemID }.reduce(0) { $0 + $1.amount }
    }

    /// What the render loop does every frame: advances the scene so objects spawn and move.
    private func tick(_ gameSession: GameSession) {
        if let runtime = gameSession.playSession?.mapRuntime {
            runtime.update(at: .now, renderTime: ProcessInfo.processInfo.systemUptime)
        }
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
        Log.line("[\(role.rawValue)] \(text)")
        steps.append(["t": (Date().timeIntervalSince(startDate) * 10).rounded() / 10, "step": text])
    }

    private func fail(_ text: String) {
        Log.line("[\(role.rawValue)] FAILED: \(text)")
        errors.append(text)
    }

    private func check(_ name: String, _ ok: Bool, detail: String) {
        Log.line("[\(role.rawValue)] check \(ok ? "PASS" : "FAIL"): \(name) \(detail)")
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
            "role": role.rawValue,
            "user": options.user,
            "character": options.charName,
            "passed": passed,
            "seconds": (Date().timeIntervalSince(startDate) * 10).rounded() / 10,
            "checks": checks,
            "errors": errors,
            "facts": facts,
            "steps": steps,
        ]
        Log.line("[\(role.rawValue)] result: \(passed ? "PASS" : "FAIL") (\(checks.filter { $0["passed"] as? Bool == true }.count)/\(checks.count) checks)")
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
