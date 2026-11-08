//
//  BuyingStoreView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

/// The buying store of another player: pick what to sell from the inventory and sell it.
struct BuyingStoreView: View {
    var store: BuyingStore

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    var body: some View {
        GameWindow {
            ScrollView {
                VStack(spacing: 0) {
                    if store.items.isEmpty {
                        Text(verbatim: "The buyer wants nothing more.")
                            .font(.game())
                            .foregroundStyle(Color.gameLabel)
                            .padding(10)
                    }

                    ForEach(store.items) { item in
                        let owned = BuyingStore.sellableAmount(of: item.itemID, in: playSession.inventory)
                        BuyingStoreItemRow(
                            item: item,
                            owned: owned,
                            quantity: Binding {
                                store.quantity(of: item.itemID)
                            } set: { newValue in
                                playSession.setBuyingStoreQuantity(newValue, of: item.itemID)
                            },
                            maxQuantity: store.maxQuantity(of: item.itemID, owned: owned)
                        )
                    }
                }
            }
            .frame(height: 220)
        } bottomBar: {
            GameBottomBar {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Total : \(store.totalPrice) Zeny")
                    Text(verbatim: "Buyer can pay : \(store.zenyLimit) Zeny")
                }
                .font(.game())
                .foregroundStyle(Color.gameLabel)

                Spacer()

                // btn_sell.bmp
                Button {
                    playSession.sellToBuyingStore()
                } label: {
                    Text("sell", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(store.problem() != nil)

                // btn_cancel.bmp
                Button {
                    playSession.closeBuyingStoreWindow()
                } label: {
                    Text("cancel", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: store.title.isEmpty ? "Buying Store" : store.title))
        .gameWindowCloseAction {
            playSession.closeBuyingStoreWindow()
        }
        .frame(width: 340)
    }
}

private struct BuyingStoreItemRow: View {
    var item: BuyingStore.Item
    var owned: Int

    @Binding var quantity: Int
    var maxQuantity: Int

    @Environment(GameContext.self) private var gameContext

    var body: some View {
        HStack(spacing: 5) {
            VendingItemIcon(itemID: item.itemID, amount: item.amount)

            VStack(alignment: .leading, spacing: 0) {
                Text(gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "\(item.itemID)")
                    .lineLimit(2)
                Text(verbatim: "You have \(owned)")
            }

            Spacer(minLength: 5)

            Text(verbatim: "\(item.price) Z")
                .lineLimit(1)

            GameStepper(value: $quantity, in: 0...max(maxQuantity, quantity))
                .padding(.horizontal, 5)
                .disabled(owned == 0)
        }
        .font(.game())
        .foregroundStyle(Color.gameLabel)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(quantity > 0 ? Color(#colorLiteral(red: 0.8039215686, green: 0.8784313725, blue: 1, alpha: 1)) : .clear)
    }
}

#Preview("Buying store") {
    let store = BuyingStore(
        buyerID: 2_000_001,
        storeID: 1,
        title: "Buying herbs",
        zenyLimit: 5_000,
        items: [
            BuyingStore.Item(itemID: 506, type: 0, price: 50, amount: 20),
            BuyingStore.Item(itemID: 507, type: 0, price: 18, amount: 100),
        ]
    )

    BuyingStoreView(store: store)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
