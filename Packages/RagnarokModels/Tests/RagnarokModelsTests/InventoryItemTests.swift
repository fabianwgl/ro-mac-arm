import RagnarokPackets
import Testing
@testable import RagnarokModels

/// Whether a dropped item is appraised decides which name the inventory shows (Knife or Dagger).
struct InventoryItemTests {
    @Test func equipItemIsIdentifiedByTheFirstFlagBit() {
        var info = EQUIPITEM_INFO()
        info.ITID = 1201

        info.Flag = 0b0000_0000
        #expect(InventoryItem(from: info).isIdentified == false)

        info.Flag = 0b0000_0001
        #expect(InventoryItem(from: info).isIdentified == true)

        // IsDamaged and PlaceETCTab do not make an item identified.
        info.Flag = 0b0000_0110
        #expect(InventoryItem(from: info).isIdentified == false)

        info.Flag = 0b0000_0111
        #expect(InventoryItem(from: info).isIdentified == true)
    }

    @Test func normalItemIsIdentifiedByTheFirstFlagBit() {
        var info = NORMALITEM_INFO()
        info.ITID = 501

        info.Flag = 0
        #expect(InventoryItem(from: info).isIdentified == false)

        info.Flag = 1
        #expect(InventoryItem(from: info).isIdentified == true)
    }

    @Test func newItemIsIdentified() {
        #expect(InventoryItem().isIdentified)
    }

    @Test func pickedUpItemKeepsTheServerFlag() {
        var inventory = Inventory()

        var packet = PACKET_ZC_ITEM_PICKUP_ACK()
        packet.Index = 5
        packet.count = 1
        packet.nameid = 1201
        packet.IsIdentified = 0
        inventory.update(from: packet)
        #expect(inventory.items[5]?.isIdentified == false)

        packet.Index = 6
        packet.nameid = 501
        packet.IsIdentified = 1
        inventory.update(from: packet)
        #expect(inventory.items[6]?.isIdentified == true)
    }

    @Test func storedItemKeepsTheServerFlag() {
        var storage = Storage(name: "Storage")

        var packet = PACKET_ZC_ADD_ITEM_TO_STORE()
        packet.index = 2
        packet.amount = 1
        packet.itemId = 1201
        packet.identified = 0
        storage.update(from: packet)
        #expect(storage.items[2]?.isIdentified == false)
    }
}
