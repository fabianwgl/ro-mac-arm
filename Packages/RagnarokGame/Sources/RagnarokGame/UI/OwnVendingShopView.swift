//
//  OwnVendingShopView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokResources
import SwiftUI

/// The player's own shop while it is open: what is left, what sold, and the button that closes it.
struct OwnVendingShopView: View {
    var shop: OwnVendingShop

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        GameWindow {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(shop.items) { item in
                        OwnVendingShopRow(item: item)
                    }
                }
            }
            .frame(height: 180)
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: "Earned : \(shop.earnedZeny) Zeny")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)

                Spacer()

                Button {
                    playSession.closeOwnVendingShop()
                } label: {
                    Text(verbatim: "Close")
                }
                .buttonStyle(.game)
                .frame(width: 56, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: shop.title))
        .gameWindowCloseAction {
            playSession.closeOwnVendingShop()
        }
        .frame(width: 320)
    }
}

private struct OwnVendingShopRow: View {
    var item: OwnVendingShop.Item

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

            Text(gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "\(item.itemID)")
                .lineLimit(2)

            Spacer(minLength: 5)

            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: "\(item.price) Z")

                if item.isSoldOut {
                    Text(verbatim: "Sold out")
                } else if item.sold > 0 {
                    Text(verbatim: "Sold \(item.sold)")
                }
            }
        }
        .font(.game())
        .foregroundStyle(Color.gameLabel)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .task(id: item.itemID) {
            iconImage = try? await gameContext.resourceManager.itemIconImage(forItemID: item.itemID)
        }
    }
}

#Preview("Open shop") {
    let shop = OwnVendingShop(title: "Cheap potions", items: [
        OwnVendingShop.Item(index: 2, itemID: 501, price: 50, amount: 20, sold: 5),
        OwnVendingShop.Item(index: 3, itemID: 502, price: 200, amount: 0, sold: 3),
    ])

    OwnVendingShopView(shop: shop)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
