//
//  VendingShopView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokConstants
import RagnarokLocalization
import RagnarokModels
import RagnarokResources
import SwiftUI

/// The shop of another player: pick the items and buy them.
struct VendingShopView: View {
    var shop: VendingShop

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    var body: some View {
        GameWindow {
            ScrollView {
                VStack(spacing: 0) {
                    if shop.items.isEmpty {
                        Text(verbatim: "The shop is empty.")
                            .font(.game())
                            .foregroundStyle(Color.gameLabel)
                            .padding(10)
                    }

                    ForEach(shop.items) { item in
                        VendingShopItemRow(
                            item: item,
                            quantity: quantityBinding(for: item),
                            maxQuantity: shop.maxQuantity(of: item.index, zeny: playSession.playerStatus.zeny)
                        )
                    }
                }
            }
            .frame(height: 220)
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: "Total : \(shop.totalPrice) Zeny")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)

                Spacer()

                // btn_buy.bmp
                Button {
                    playSession.purchaseFromVendingShop()
                } label: {
                    Text("buy", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(shop.problem(zeny: playSession.playerStatus.zeny) != nil)

                // btn_cancel.bmp
                Button {
                    playSession.closeVendingShopWindow()
                } label: {
                    Text("cancel", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: shop.title.isEmpty ? "Shop" : shop.title))
        .gameWindowCloseAction {
            playSession.closeVendingShopWindow()
        }
        .frame(width: 340)
    }

    private func quantityBinding(for item: VendingShop.Item) -> Binding<Int> {
        Binding {
            shop.quantity(of: item.index)
        } set: { newValue in
            playSession.setVendingQuantity(newValue, of: item.index)
        }
    }
}

/// The name of an item as shops list it, with its refine level.
/// rAthena only lets identified items into a shop, so there is no unidentified name.
func vendingItemName(itemID: Int, refine: Int, isIdentified: Bool = true, itemInfoTable: ItemInfoTable) -> String {
    let name = itemInfoTable.localizedItemName(forItemID: itemID, isIdentified: isIdentified) ?? "\(itemID)"
    return refine > 0 ? "+\(refine) \(name)" : name
}

private struct VendingShopItemRow: View {
    var item: VendingShop.Item

    @Binding var quantity: Int
    var maxQuantity: Int

    @Environment(GameContext.self) private var gameContext

    @State private var iconImage: Resources.Image?

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .center) {
                GameItemShadowView()
                    .offset(y: 5)

                if let iconImage {
                    Image(decorative: iconImage.cgImage, scale: 1)
                }

                Text(verbatim: "\(item.amount)")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .shadow(color: .white, radius: 1)
                    .offset(x: 5, y: 10)
            }
            .frame(width: 32, height: 32)

            Text(vendingItemName(itemID: item.itemID, refine: item.refine, isIdentified: item.isIdentified, itemInfoTable: gameContext.itemInfoTable))
            .lineLimit(2)

            Spacer(minLength: 5)

            Text(verbatim: "\(item.price) Z")
                .lineLimit(1)

            GameStepper(value: $quantity, in: 0...max(maxQuantity, quantity))
                .padding(.horizontal, 5)
        }
        .font(.game())
        .foregroundStyle(Color.gameLabel)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(quantity > 0 ? Color(#colorLiteral(red: 0.8039215686, green: 0.8784313725, blue: 1, alpha: 1)) : .clear)
        .task(id: item.itemID) {
            iconImage = try? await gameContext.resourceManager.itemIconImage(forItemID: item.itemID)
        }
    }
}

#Preview("Shop") {
    let shop = VendingShop(
        vendorID: 2_000_001,
        shopID: 1,
        title: "Cheap potions",
        items: [
            VendingShop.Item(index: 2, itemID: 501, price: 50, amount: 20),
            VendingShop.Item(index: 3, itemID: 1201, type: 4, price: 1_200, amount: 1, refine: 4),
        ]
    )

    VendingShopView(shop: shop)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
