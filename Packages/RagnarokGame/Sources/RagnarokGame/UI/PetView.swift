//
//  PetView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokCore
import RagnarokModels
import RagnarokResources
import SwiftUI

/// The pet window: status, the pet commands, rename and auto feed.
struct PetView: View {
    var pet: PetState
    var onClose: () -> Void = {}

    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    @State private var newName = ""

    var body: some View {
        GameWindow {
            VStack(alignment: .leading, spacing: 5) {
                if pet.isActive {
                    header
                    meters
                    accessoryRow

                    if pet.canRename {
                        CompanionRenameForm(name: $newName) {
                            playSession.renamePet(to: newName)
                            newName = ""
                        }
                    }

                    commandRow
                } else {
                    emptyState
                }
            }
            .padding(5)
        } bottomBar: {
            GameBottomBar {
                if pet.isActive {
                    Button {
                        playSession.setPetAutoFeed(!pet.isAutoFeedEnabled)
                    } label: {
                        Text(verbatim: "Auto feed: \(pet.isAutoFeedEnabled ? "On" : "Off")")
                    }
                    .buttonStyle(.game)
                    .frame(width: 96, height: 20)
                }
            }
        }
        .gameWindowTitle(Text(verbatim: "Pet"))
        .gameWindowCloseAction(onClose)
        .frame(width: 320)
        .onAppear {
            // The server sends the pet when it enters the map. Asking again covers a pet which
            // was already out, and costs nothing when there is none.
            if !pet.isActive {
                playSession.requestPetInformation()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(verbatim: pet.name)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(verbatim: "Lv \(pet.level)")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
        }
        .padding(5)
        .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9568627451, blue: 0.9411764706, alpha: 1)))
    }

    private var meters: some View {
        VStack(alignment: .leading, spacing: 4) {
            CompanionMeterRow(
                title: "Hunger",
                fraction: pet.hungerFraction,
                color: .orange,
                detail: "\(pet.hungerLevel.title) (\(pet.hunger)/\(PetState.maxHunger))"
            )
            CompanionMeterRow(
                title: "Intimacy",
                fraction: pet.intimacyFraction,
                color: .pink,
                detail: "\(pet.intimacyLevel.title) (\(pet.intimacy)/\(PetState.maxIntimacy))"
            )
        }
        .padding(.horizontal, 5)
    }

    private var accessoryRow: some View {
        HStack(spacing: 6) {
            Text(verbatim: "Accessory")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
                .frame(width: 60, alignment: .leading)

            Text(verbatim: accessoryName)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
    }

    private var commandRow: some View {
        HStack(spacing: 5) {
            Button {
                playSession.feedPet()
            } label: {
                Text(verbatim: "Feed")
            }
            .buttonStyle(.game)
            .frame(width: 50, height: 20)

            Button {
                playSession.performPet()
            } label: {
                Text(verbatim: "Perform")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)

            Button {
                playSession.returnPetToEgg()
            } label: {
                Text(verbatim: "To egg")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)

            Button {
                playSession.unequipPetAccessory()
            } label: {
                Text(verbatim: "Unequip")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)
            .disabled(!pet.hasAccessory)

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "You have no pet.")
                .font(.game())
                .foregroundStyle(Color.gameLabel)

            Text(verbatim: "Tame a monster with its lure, then hatch the egg with a Pet Incubator.")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    private var accessoryName: String {
        guard pet.hasAccessory else {
            return "None"
        }
        return gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: pet.accessoryItemID)
            ?? "Item \(pet.accessoryItemID)"
    }
}

/// The window a pet incubator opens: the eggs which can be hatched.
struct PetEggListView: View {
    var inventory: Inventory
    var eggIndices: [Int]

    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    var body: some View {
        GameWindow {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if eggIndices.isEmpty {
                        Text(verbatim: "You have no pet eggs.")
                            .font(.game(size: 11))
                            .foregroundStyle(Color.gameProminentLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    ForEach(eggIndices, id: \.self) { index in
                        Button {
                            playSession.selectPetEgg(inventoryIndex: index)
                        } label: {
                            PetEggRow(item: inventory.items[index], name: eggName(at: index))
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
                    playSession.cancelPetEggSelection()
                } label: {
                    Text(verbatim: "Cancel")
                }
                .buttonStyle(.game)
                .frame(width: 58, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: "Hatch a pet egg"))
        .gameWindowCloseAction {
            playSession.cancelPetEggSelection()
        }
        .frame(width: 300)
    }

    private func eggName(at index: Int) -> String {
        guard let item = inventory.items[index] else {
            return "Pet egg"
        }
        return gameContext.itemInfoTable.localizedItemName(forItemID: item.itemID, isIdentified: item.isIdentified) ?? "Item \(item.itemID)"
    }
}

private struct PetEggRow: View {
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

// MARK: - Shared Pieces

/// A label, a filled bar and a detail text, such as hunger or HP.
struct CompanionMeterRow: View {
    var title: String
    var fraction: Double
    var color: Color
    var detail: String

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
                .frame(width: 60, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.black.opacity(0.15))

                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(width: 90, height: 6)

            Text(verbatim: detail)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

/// A name field with a button, for renaming a pet or a homunculus.
struct CompanionRenameForm: View {
    @Binding var name: String
    var onRename: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            TextField("New name", text: $name)
                .textFieldStyle(.plain)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(.horizontal, 3)
                .frame(height: 18)
                .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9372549020, blue: 0.9372549020, alpha: 1)))
                .onSubmit(onRename)

            Button(action: onRename) {
                Text(verbatim: "Rename")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)
            .disabled(CompanionName.validated(name) == nil)
        }
    }
}

#Preview {
    let pet: PetState = {
        var pet = PetState()
        pet.applyProperties(
            name: "Poring",
            isRenamed: false,
            level: 3,
            hunger: 60,
            intimacy: 420,
            accessoryItemID: 0,
            classID: 1002
        )
        return pet
    }()

    PetView(pet: pet)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
