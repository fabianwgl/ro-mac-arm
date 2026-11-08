//
//  BuyingStoreSetupView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokModels
import SwiftUI

/// The window of a buying store license: pick what to buy, how many and for how much, and open the store.
///
/// The server only lets a player buy items he already owns at least one of, so the rows are his inventory.
struct BuyingStoreSetupView: View {
    var setup: BuyingStoreSetup

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    var body: some View {
        GameWindow {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Text(verbatim: "Title")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)

                    textField(text: Binding {
                        setup.title
                    } set: { newValue in
                        playSession.setBuyingStoreTitle(newValue)
                    })
                }
                .padding(5)

                HStack(spacing: 5) {
                    Text(verbatim: "Spend at most")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)

                    VendingPriceField(price: Binding {
                        setup.zenyLimit
                    } set: { newValue in
                        playSession.setBuyingStoreZenyLimit(newValue)
                    })

                    Text(verbatim: "Zeny")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)

                    Spacer()

                    Text(verbatim: "\(setup.pickedItemIDs.count) / \(setup.slots) items")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 5)

                ScrollView {
                    VStack(spacing: 0) {
                        let items = distinctInventoryItems
                        if items.isEmpty {
                            Text(verbatim: "The inventory is empty.")
                                .font(.game())
                                .foregroundStyle(Color.gameLabel)
                                .padding(10)
                        }

                        ForEach(items, id: \.itemID) { item in
                            BuyingStoreSetupRow(
                                item: item,
                                amount: Binding {
                                    setup.amount(of: item.itemID)
                                } set: { newValue in
                                    playSession.setBuyingStoreAmount(newValue, forItemID: item.itemID)
                                },
                                price: Binding {
                                    setup.price(of: item.itemID)
                                } set: { newValue in
                                    playSession.setBuyingStorePrice(newValue, forItemID: item.itemID)
                                }
                            )
                        }
                    }
                }
                .frame(height: 220)
            }
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: "Total : \(setup.totalCost) Zeny")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)

                Spacer()

                // btn_ok.bmp
                Button {
                    playSession.openBuyingStore()
                } label: {
                    Text("OK", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(setup.isSending || setup.problem(inventory: playSession.inventory, zeny: playSession.playerStatus.zeny) != nil)

                // btn_cancel.bmp
                Button {
                    playSession.cancelBuyingStoreSetup()
                } label: {
                    Text("cancel", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: "Open Buying Store"))
        .gameWindowCloseAction {
            playSession.cancelBuyingStoreSetup()
        }
        .frame(width: 360)
    }

    /// One row per item the player owns, worn items left out.
    private var distinctInventoryItems: [InventoryItem] {
        var seen: Set<Int> = []
        return playSession.inventory.items.values.sorted().filter { item in
            !item.isEquipped && seen.insert(item.itemID).inserted
        }
    }

    private func textField(text: Binding<String>) -> some View {
        TextField(String(), text: text)
            .textFieldStyle(.plain)
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 4)
            .frame(height: 18)
            .background(Color(#colorLiteral(red: 0.9686274510, green: 0.9686274510, blue: 0.9686274510, alpha: 1)))
            .border(Color(#colorLiteral(red: 0.7764705882, green: 0.7764705882, blue: 0.7764705882, alpha: 1)))
    }
}

private struct BuyingStoreSetupRow: View {
    var item: InventoryItem

    @Binding var amount: Int
    @Binding var price: Int

    @Environment(GameContext.self) private var gameContext

    var body: some View {
        HStack(spacing: 5) {
            VendingItemIcon(itemID: item.itemID, amount: item.amount)

            Text(gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "\(item.itemID)")
                .lineLimit(2)

            Spacer(minLength: 5)

            VendingPriceField(price: $price)

            GameStepper(value: $amount, in: 0...BuyingStoreSetup.maxAmount)
                .padding(.horizontal, 5)
        }
        .font(.game())
        .foregroundStyle(Color.gameLabel)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(amount > 0 ? Color(#colorLiteral(red: 0.8039215686, green: 0.8784313725, blue: 1, alpha: 1)) : .clear)
    }
}

/// The player's own buying store while it is open.
struct OwnBuyingStoreView: View {
    var store: OwnBuyingStore

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    var body: some View {
        GameWindow {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.items) { item in
                        HStack(spacing: 5) {
                            VendingItemIcon(itemID: item.itemID, amount: item.amount)

                            Text(gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "\(item.itemID)")
                                .lineLimit(2)

                            Spacer(minLength: 5)

                            VStack(alignment: .trailing, spacing: 0) {
                                Text(verbatim: "\(item.price) Z")
                                if item.amount == 0 {
                                    Text(verbatim: "Bought all")
                                } else if item.bought > 0 {
                                    Text(verbatim: "Bought \(item.bought)")
                                }
                            }
                        }
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(height: 140)
        } bottomBar: {
            GameBottomBar {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Spent : \(store.spentZeny) Zeny")
                    Text(verbatim: "Left to spend : \(store.zenyLimit) Zeny")
                }
                .font(.game())
                .foregroundStyle(Color.gameLabel)

                Spacer()

                Button {
                    playSession.closeOwnBuyingStore()
                } label: {
                    Text(verbatim: "Close")
                }
                .buttonStyle(.game)
                .frame(width: 56, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: store.title))
        .gameWindowCloseAction {
            playSession.closeOwnBuyingStore()
        }
        .frame(width: 320)
    }
}
