//
//  ItemAppraisalView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokCore
import RagnarokModels
import RagnarokResources
import SwiftUI

/// The window a Magnifier or the Item Appraisal skill opens: the unidentified items which can be appraised.
struct ItemAppraisalView: View {
    var inventory: Inventory
    var candidateIndices: [Int]

    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    var body: some View {
        GameWindow {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if candidateIndices.isEmpty {
                        Text(verbatim: "There are no items to appraise.")
                            .font(.game(size: 11))
                            .foregroundStyle(Color.gameProminentLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    ForEach(candidateIndices, id: \.self) { index in
                        Button {
                            playSession.appraiseItem(at: index)
                        } label: {
                            ItemAppraisalRow(item: inventory.items[index], name: itemName(at: index))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 160)
            .background(Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1)))
            .padding(5)
        } bottomBar: {
            GameBottomBar {
                Button {
                    playSession.cancelAppraisal()
                } label: {
                    Text(verbatim: "Cancel")
                }
                .buttonStyle(.game)
                .frame(width: 58, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: "Item Appraisal"))
        .gameWindowCloseAction {
            playSession.cancelAppraisal()
        }
        .frame(width: 300)
    }

    private func itemName(at index: Int) -> String {
        guard let item = inventory.items[index] else {
            return "Item \(index)"
        }
        return gameContext.itemInfoTable.localizedItemName(forItemID: item.itemID, isIdentified: item.isIdentified) ?? "Item \(item.itemID)"
    }
}

private struct ItemAppraisalRow: View {
    var item: InventoryItem?
    var name: String

    @Environment(GameContext.self) private var gameContext

    @State private var iconImage: Resources.Image?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if let iconImage {
                    Image(decorative: iconImage.cgImage, scale: 1)
                }
            }
            .frame(width: 24, height: 24)

            Text(verbatim: name)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 15)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .task(id: item?.itemID) {
            guard let itemID = item?.itemID else {
                return
            }
            iconImage = try? await gameContext.resourceManager.itemIconImage(forItemID: itemID)
        }
    }
}

#Preview {
    let inventory = {
        var inventory = Inventory()

        var knife = InventoryItem()
        knife.index = 2
        knife.itemID = 1201
        knife.type = .weapon
        knife.amount = 1
        knife.isIdentified = false
        inventory.append(item: knife)

        var cotton = InventoryItem()
        cotton.index = 3
        cotton.itemID = 2301
        cotton.type = .armor
        cotton.amount = 1
        cotton.isIdentified = false
        inventory.append(item: cotton)

        return inventory
    }()

    ItemAppraisalView(inventory: inventory, candidateIndices: [2, 3])
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
