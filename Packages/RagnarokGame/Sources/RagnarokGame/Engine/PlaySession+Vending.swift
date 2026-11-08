//
//  PlaySession+Vending.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokModels
import RagnarokNetwork
import RagnarokPackets

@Observable
final class VendingState {
    /// The titles of the shop signs in view, by account id of the vendor (`ZC_STORE_ENTRY`).
    /// A vendor is a player standing on the map with a shop open.
    var signs: [UInt32 : String] = [:]

    /// The shop of another player that the player is looking at, with the window open while this is not nil.
    var shop: VendingShop?

    /// The player's pushcart. Vending takes its items from it.
    var cart = Cart()

    /// The shop set up window, open while this is not nil. The Vending skill opens it (`ZC_OPENSTORE`).
    var setup: VendingSetup?

    /// The player's own shop, once the server opened it.
    var ownShop: OwnVendingShop?

    /// The title that went out with the request to open the shop, which the server's answer does not repeat.
    @ObservationIgnored var pendingShopTitle = ""

    /// The buying stores, which are the shops turned around (PlaySession+BuyingStore.swift).
    var buying = BuyingStoreState()

    /// The item id of cart slots that were just emptied, by cart index. rAthena removes the item from the cart
    /// (`ZC_DELETE_ITEM_FROM_CART`) before it reports the sale (`ZC_DELETEITEM_FROM_MCSTORE`), so the report
    /// finds its item here.
    @ObservationIgnored var recentlyRemovedCartItemIDs: [Int : (itemID: Int, isIdentified: Bool)] = [:]

    /// The signs and the shop window belong to the map the player left.
    func resetForMapChange() {
        signs = [:]
        shop = nil
        setup = nil
        ownShop = nil
        buying.resetForMapChange()
    }

    /// A player left the view: his shop or buying store sign goes with him.
    func removeSigns(of objectID: UInt32) {
        signs.removeValue(forKey: objectID)
        buying.signs.removeValue(forKey: objectID)
    }
}

extension PlaySession {
    /// Handles shop and cart packets. Returns false when the packet is neither.
    func handleVendingPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_STORE_ENTRY:
            vending.signs[packet.makerAID] = packet.storeName
        case let packet as PACKET_ZC_DISAPPEAR_ENTRY:
            handleVendingBoardRemoved(vendorID: UInt32(bitPattern: packet.GID))
        case let packet as PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC:
            let title = vending.signs[packet.AID] ?? ""
            vending.shop = VendingShop(from: packet, title: title)
        case let packet as PACKET_ZC_PC_PURCHASE_RESULT_FROMMC:
            handleVendingPurchaseResult(packet)
        case let packet as PACKET_ZC_DELETEITEM_FROM_MCSTORE:
            handleVendingSale(packet)

        // The player's own shop.
        case let packet as PACKET_ZC_OPENSTORE:
            vending.setup = VendingSetup(slots: Int(packet.num))
        case let packet as PACKET_ZC_PC_PURCHASE_MYITEMLIST:
            vending.ownShop = OwnVendingShop(from: packet, title: vending.pendingShopTitle)
        case let packet as PACKET_ZC_ACK_OPENSTORE2:
            handleOpenStoreAck(packet)

        // The cart. Inventory type 1 of the item lists, the other types belong to the inventory and the storage.
        case let packet as PACKET_ZC_INVENTORY_START where Int(packet.invType) == Cart.inventoryType:
            vending.cart.items = [:]
            vending.cart.isActive = true
        case let packet as PACKET_ZC_INVENTORY_END where Int(packet.invType) == Cart.inventoryType:
            break
        case let packet as packet_itemlist_normal where Int(packet.invType) == Cart.inventoryType:
            vending.cart.update(from: packet)
        case let packet as packet_itemlist_equip where Int(packet.invType) == Cart.inventoryType:
            vending.cart.update(from: packet)
        case let packet as PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO:
            vending.cart.update(from: packet)
        case let packet as PACKET_ZC_ADD_ITEM_TO_CART:
            vending.cart.update(from: packet)
        case let packet as PACKET_ZC_DELETE_ITEM_FROM_CART:
            let index = Int(packet.index)
            if let item = vending.cart.items[index] {
                vending.recentlyRemovedCartItemIDs[index] = (itemID: item.itemID, isIdentified: item.isIdentified)
            }
            vending.cart.update(from: packet)
        case _ as PACKET_ZC_CARTOFF:
            vending.cart.clear()
        case let packet as PACKET_ZC_ACK_ADDITEM_TO_CART:
            messageCenter.addMessage(for: packet)
        default:
            return handleBuyingStorePacket(packet)
        }
        return true
    }

    // MARK: - Browsing and buying

    /// Asks a vendor for the item list of the shop. The server answers with the list, or says nothing
    /// when the player is not vending any more.
    func requestVendingList(vendorID: UInt32) {
        sendPacket(PacketFactory.CZ_REQ_BUY_FROMMC(vendorID: vendorID))
    }

    /// Whether the player on the map with this account id has a shop open.
    func hasVendingShop(vendorID: UInt32) -> Bool {
        vending.signs[vendorID] != nil
    }

    func closeVendingShopWindow() {
        vending.shop = nil
    }

    func setVendingQuantity(_ quantity: Int, of index: Int) {
        vending.shop?.setQuantity(quantity, of: index)
    }

    /// Sends the picked items. rAthena forgets the shop the player was looking at after every purchase,
    /// whether it works or not, so the window closes.
    func purchaseFromVendingShop() {
        guard let shop = vending.shop else {
            return
        }

        if let problem = shop.problem(zeny: playerStatus.zeny) {
            addVendingMessage(problem.message, type: .error)
            return
        }

        // rAthena drops a purchase from farther away without an answer.
        if let distance = distanceToVendor(shop.vendorID), distance > VendingShop.maxPurchaseDistance {
            addVendingMessage(VendingShop.Problem.tooFarAway.message, type: .error)
            return
        }

        let purchases = shop.purchases.map { (index: $0.index, count: $0.count) }
        sendPacket(PacketFactory.CZ_PC_PURCHASE_ITEMLIST_FROMMC2(
            vendorID: shop.vendorID,
            shopID: shop.shopID,
            purchases: purchases
        ))
        vending.shop = nil
    }

    /// Cells between the player and the vendor, or nil when the vendor is not in view.
    private func distanceToVendor(_ vendorID: UInt32) -> Int? {
        guard let scene = mapScene, let vendor = scene.objects[vendorID] else {
            return nil
        }
        let delta = scene.player.gridPosition &- vendor.gridPosition
        return max(abs(delta.x), abs(delta.y))
    }

    // MARK: - Own shop

    func setVendingTitle(_ title: String) {
        vending.setup?.setTitle(title)
    }

    /// Sells `amount` of the cart item. Zero takes it out of the shop.
    func setVendingAmount(_ amount: Int, forCartIndex index: Int) {
        let available = vending.cart.items[index]?.amount ?? 0
        vending.setup?.setAmount(amount, for: index, available: available)
    }

    func setVendingPrice(_ price: Int, forCartIndex index: Int) {
        vending.setup?.setPrice(price, for: index)
    }

    /// Sends the shop. The window stays until the server answers with the shop or a refusal.
    func openVendingShop() {
        guard var setup = vending.setup, !setup.isSending else {
            return
        }

        if let problem = setup.problem(cart: vending.cart) {
            addVendingMessage(problem.message, type: .error)
            return
        }

        vending.pendingShopTitle = setup.title
        setup.isSending = true
        vending.setup = setup
        sendPacket(PacketFactory.CZ_REQ_OPENSTORE2(title: setup.title, items: setup.requestItems))
    }

    /// Closes the set up window. rAthena keeps the player from using the skill again until it hears
    /// either the shop or the cancel.
    func cancelVendingSetup() {
        guard vending.setup != nil else {
            return
        }
        vending.setup = nil
        sendPacket(PacketFactory.CZ_REQ_OPENSTORE2(title: "", items: []))
    }

    /// Takes the player's own shop down.
    func closeOwnVendingShop() {
        guard vending.ownShop != nil else {
            return
        }
        vending.ownShop = nil
        vending.signs.removeValue(forKey: account.accountID)
        sendPacket(PacketFactory.CZ_REQ_CLOSESTORE())
    }

    // MARK: - Cart

    /// Whether the inventory menu offers to move the item into the cart: the player has a cart, and the server
    /// keeps equipped items out of it.
    func canMoveToCart(_ item: InventoryItem) -> Bool {
        vending.cart.isActive && !item.isEquipped && item.amount > 0
    }

    /// Moves an item of the inventory into the cart (`CZ_MOVE_ITEM_FROM_BODY_TO_CART`).
    func moveItemToCart(index: Int, amount: Int) {
        sendPacket(PacketFactory.CZ_MOVE_ITEM_FROM_BODY_TO_CART(index: index, amount: amount))
    }

    /// Moves an item of the cart back into the inventory (`CZ_MOVE_ITEM_FROM_CART_TO_BODY`).
    func moveItemFromCart(index: Int, amount: Int) {
        sendPacket(PacketFactory.CZ_MOVE_ITEM_FROM_CART_TO_BODY(index: index, amount: amount))
    }

    // MARK: - Packets

    private func handleVendingBoardRemoved(vendorID: UInt32) {
        vending.signs.removeValue(forKey: vendorID)

        if vending.shop?.vendorID == vendorID {
            vending.shop = nil
            addVendingMessage("The shop was closed.", type: .info)
        }
    }

    /// rAthena sends this for failures only, `PURCHASEMC_SUCCESS` never goes out: a purchase that works shows
    /// as the new item, the lower zeny and the pickup message.
    private func handleVendingPurchaseResult(_ packet: PACKET_ZC_PC_PURCHASE_RESULT_FROMMC) {
        guard let message = Self.vendingPurchaseFailureMessage(forResult: packet.result) else {
            return
        }
        addVendingMessage(message, type: .error)
    }

    static func vendingPurchaseFailureMessage(forResult result: UInt8) -> String? {
        // `enum e_pc_purchase_result_frommc` in clif.hpp.
        switch result {
        case 0: nil
        case 1: "You do not have enough zeny."
        case 2: "You cannot carry that much weight."
        case 4: "The shop does not have that many left."
        case 5: "You cannot buy while trading."
        case 6: "The shop information was incorrect, nothing was bought."
        case 7: "The shop has no sales information."
        default: "The purchase failed."
        }
    }

    /// The vendor side: someone bought `amount` of the cart item `index` for `zeny` (after tax).
    private func handleVendingSale(_ packet: PACKET_ZC_DELETEITEM_FROM_MCSTORE) {
        let index = Int(packet.index)
        let sold: (itemID: Int, isIdentified: Bool)? = vending.ownShop?.item(at: index).map { ($0.itemID, $0.isIdentified) }
            ?? vending.cart.items[index].map { ($0.itemID, $0.isIdentified) }
            ?? vending.recentlyRemovedCartItemIDs[index]
        let itemID = sold?.itemID
        vending.recentlyRemovedCartItemIDs.removeValue(forKey: index)

        let itemName = sold.flatMap { messageCenter.itemInfoTable.localizedItemName(forItemID: $0.itemID, isIdentified: $0.isIdentified) }
            ?? itemID.map { "item \($0)" }
            ?? "an item"
        addVendingMessage("Sold \(packet.amount) \(itemName) for \(packet.zeny) zeny.", type: .system)

        vending.ownShop?.recordSale(index: index, amount: Int(packet.amount), zeny: Int(packet.zeny))

        // rAthena leaves an empty shop open, the official client closes it.
        if let ownShop = vending.ownShop, ownShop.isSoldOut {
            addVendingMessage("Everything is sold, the shop is closed. It earned \(ownShop.earnedZeny) zeny.", type: .info)
            closeOwnVendingShop()
        }
    }

    /// The answer to `CZ_REQ_OPENSTORE2`, which follows the item list of the shop. `e_ack_openstore2` in clif.hpp.
    private func handleOpenStoreAck(_ packet: PACKET_ZC_ACK_OPENSTORE2) {
        vending.setup = nil

        if packet.result == 0, let ownShop = vending.ownShop {
            vending.signs[account.accountID] = ownShop.title
            addVendingMessage("Your shop \"\(ownShop.title)\" is open.", type: .system)
        } else {
            vending.ownShop = nil
            let message = packet.result == 3
                ? "You cannot open a shop at this location."
                : "The shop could not be opened."
            addVendingMessage(message, type: .error)
        }
    }

    func addVendingMessage(_ content: String, type: MessageCenter.MessageType) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}
