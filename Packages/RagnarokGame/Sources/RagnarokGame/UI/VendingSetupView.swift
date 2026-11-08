//
//  VendingSetupView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokModels
import RagnarokResources
import SwiftUI

/// The window of the Vending skill: pick cart items, set prices and a title, and open the shop.
struct VendingSetupView: View {
    var setup: VendingSetup

    private enum Source {
        case cart
        case inventory
    }

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    @State private var source: Source = .cart

    var body: some View {
        GameWindow {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Text(verbatim: "Title")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)

                    TextField(String(), text: titleBinding)
                        .textFieldStyle(.plain)
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)
                        .padding(.horizontal, 4)
                        .frame(height: 18)
                        .background(Color(#colorLiteral(red: 0.9686274510, green: 0.9686274510, blue: 0.9686274510, alpha: 1)))
                        .border(Color(#colorLiteral(red: 0.7764705882, green: 0.7764705882, blue: 0.7764705882, alpha: 1)))
                }
                .padding(5)

                HStack(spacing: 5) {
                    sourceButton(.cart, title: "Cart (\(playSession.vending.cart.items.count))")
                    sourceButton(.inventory, title: "Inventory")

                    Spacer()

                    Text(verbatim: "\(setup.pickedIndices.count) / \(setup.slots) items")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 5)

                ScrollView {
                    VStack(spacing: 0) {
                        switch source {
                        case .cart:
                            cartRows
                        case .inventory:
                            inventoryRows
                        }
                    }
                }
                .frame(height: 220)
            }
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: "Total : \(setup.totalValue) Zeny")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)

                Spacer()

                // btn_ok.bmp
                Button {
                    playSession.openVendingShop()
                } label: {
                    Text("OK", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(setup.isSending || setup.problem(cart: playSession.vending.cart) != nil)

                // btn_cancel.bmp
                Button {
                    playSession.cancelVendingSetup()
                } label: {
                    Text("cancel", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: "Open Shop"))
        .gameWindowCloseAction {
            playSession.cancelVendingSetup()
        }
        .frame(width: 360)
    }

    @ViewBuilder private var cartRows: some View {
        let items = playSession.vending.cart.sortedItems
        if items.isEmpty {
            Text(verbatim: "The cart is empty. Move items from the inventory into it.")
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(10)
        }

        ForEach(items, id: \.index) { item in
            VendingSetupCartRow(
                item: item,
                amount: Binding {
                    setup.amount(of: item.index)
                } set: { newValue in
                    playSession.setVendingAmount(newValue, forCartIndex: item.index)
                },
                price: Binding {
                    setup.price(of: item.index)
                } set: { newValue in
                    playSession.setVendingPrice(newValue, forCartIndex: item.index)
                }
            )
        }
    }

    @ViewBuilder private var inventoryRows: some View {
        let items = playSession.inventory.items.values.sorted().filter { !$0.isEquipped }
        if items.isEmpty {
            Text(verbatim: "The inventory is empty.")
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(10)
        }

        ForEach(items, id: \.index) { item in
            VendingInventoryRow(item: item)
        }
    }

    private func sourceButton(_ source: Source, title: String) -> some View {
        Button {
            self.source = source
        } label: {
            Text(verbatim: title)
                .font(.game())
                .underline(self.source == source)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.gameLabel)
    }

    private var titleBinding: Binding<String> {
        Binding {
            setup.title
        } set: { newValue in
            playSession.setVendingTitle(newValue)
        }
    }
}

/// A cart item: how many to sell and for how much each.
private struct VendingSetupCartRow: View {
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

            GameStepper(value: $amount, in: 0...item.amount)
                .padding(.horizontal, 5)
        }
        .font(.game())
        .foregroundStyle(Color.gameLabel)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(amount > 0 ? Color(#colorLiteral(red: 0.8039215686, green: 0.8784313725, blue: 1, alpha: 1)) : .clear)
    }
}

/// An inventory item that can go into the cart.
private struct VendingInventoryRow: View {
    var item: InventoryItem

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    @State private var amount = 1

    var body: some View {
        HStack(spacing: 5) {
            VendingItemIcon(itemID: item.itemID, amount: item.amount)

            Text(gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "\(item.itemID)")
                .lineLimit(2)

            Spacer(minLength: 5)

            if item.amount > 1 {
                GameStepper(value: $amount, in: 1...item.amount)
                    .padding(.horizontal, 5)
            }

            Button {
                playSession.moveItemToCart(index: item.index, amount: min(max(amount, 1), item.amount))
            } label: {
                Text(verbatim: "To cart")
            }
            .buttonStyle(.game)
            .frame(width: 56, height: 20)
        }
        .font(.game())
        .foregroundStyle(Color.gameLabel)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
    }
}

struct VendingItemIcon: View {
    var itemID: Int
    var amount: Int

    @Environment(GameContext.self) private var gameContext

    @State private var iconImage: Resources.Image?

    var body: some View {
        ZStack(alignment: .center) {
            GameItemShadowView()
                .offset(y: 5)

            if let iconImage {
                Image(decorative: iconImage.cgImage, scale: 1)
            }

            Text(verbatim: "\(amount)")
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .shadow(color: .white, radius: 1)
                .offset(x: 5, y: 10)
        }
        .frame(width: 32, height: 32)
        .task(id: itemID) {
            iconImage = try? await gameContext.resourceManager.itemIconImage(forItemID: itemID)
        }
    }
}

/// A price typed as digits.
struct VendingPriceField: View {
    @Binding var price: Int

    @State private var text = ""

    var body: some View {
        TextField(String(), text: $text, prompt: Text(verbatim: "price"))
            .textFieldStyle(.plain)
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 4)
            .frame(width: 84, height: 18)
            .background(Color(#colorLiteral(red: 0.9686274510, green: 0.9686274510, blue: 0.9686274510, alpha: 1)))
            .border(Color(#colorLiteral(red: 0.7764705882, green: 0.7764705882, blue: 0.7764705882, alpha: 1)))
            #if !os(macOS)
            .keyboardType(.numberPad)
            #endif
            .onChange(of: text) {
                let digits = text.filter(\.isNumber)
                if digits != text {
                    text = digits
                }
                price = Int(digits) ?? 0
            }
            .onChange(of: price, initial: true) {
                // The model may cap the price.
                if price != (Int(text) ?? 0) {
                    text = price == 0 ? "" : "\(price)"
                }
            }
    }
}

#Preview("Set up") {
    let playSession = PlaySession.testing

    var potion = InventoryItem()
    potion.index = 2
    potion.itemID = 501
    potion.amount = 30
    playSession.vending.cart.items[2] = potion

    var setup = VendingSetup(slots: 5)
    setup.setTitle("Cheap potions")
    setup.setAmount(10, for: 2, available: 30)
    setup.setPrice(50, for: 2)

    return VendingSetupView(setup: setup)
        .padding()
        .environment(GameContext.testing)
        .environment(playSession)
}
