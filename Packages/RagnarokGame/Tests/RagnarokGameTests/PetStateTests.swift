//
//  PetStateTests.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokGame

struct PetStateTests {
    private func activePet(
        name: String = "Poring",
        isRenamed: Bool = false,
        hunger: Int = 60,
        intimacy: Int = 420,
        accessoryItemID: Int = 0
    ) -> PetState {
        var pet = PetState()
        pet.applyProperties(
            name: name,
            isRenamed: isRenamed,
            level: 3,
            hunger: hunger,
            intimacy: intimacy,
            accessoryItemID: accessoryItemID,
            classID: 1002
        )
        return pet
    }

    @Test func newStateHasNoPet() {
        let pet = PetState()
        #expect(pet.isActive == false)
        #expect(pet.canRename == false)
        #expect(pet.hasAccessory == false)
        #expect(pet.objectID == nil)
    }

    @Test func applyPropertiesFillsTheStatus() {
        let pet = activePet(accessoryItemID: 10001)

        #expect(pet.isActive)
        #expect(pet.name == "Poring")
        #expect(pet.level == 3)
        #expect(pet.hunger == 60)
        #expect(pet.intimacy == 420)
        #expect(pet.classID == 1002)
        #expect(pet.hasAccessory)
        #expect(pet.accessoryItemID == 10001)
    }

    @Test func applyPropertiesClampsValues() {
        let pet = activePet(hunger: 250, intimacy: -5)

        #expect(pet.hunger == PetState.maxHunger)
        #expect(pet.intimacy == 0)
        #expect(pet.hungerFraction == 1)
        #expect(pet.intimacyFraction == 0)
    }

    @Test func renameFlagBlocksRenaming() {
        #expect(activePet(isRenamed: false).canRename)
        #expect(activePet(isRenamed: true).canRename == false)
    }

    @Test func hungerLevelsFollowRathenaThresholds() {
        #expect(CompanionHunger(value: 0) == .veryHungry)
        #expect(CompanionHunger(value: 10) == .veryHungry)
        #expect(CompanionHunger(value: 11) == .hungry)
        #expect(CompanionHunger(value: 25) == .hungry)
        #expect(CompanionHunger(value: 26) == .neutral)
        #expect(CompanionHunger(value: 75) == .neutral)
        #expect(CompanionHunger(value: 76) == .satisfied)
        #expect(CompanionHunger(value: 90) == .satisfied)
        #expect(CompanionHunger(value: 91) == .stuffed)
        #expect(CompanionHunger(value: 100) == .stuffed)
    }

    @Test func intimacyLevelsFollowRathenaThresholds() {
        #expect(PetState.Intimacy(value: 0) == .awkward)
        #expect(PetState.Intimacy(value: 99) == .awkward)
        #expect(PetState.Intimacy(value: 100) == .shy)
        #expect(PetState.Intimacy(value: 249) == .shy)
        #expect(PetState.Intimacy(value: 250) == .neutral)
        #expect(PetState.Intimacy(value: 749) == .neutral)
        #expect(PetState.Intimacy(value: 750) == .cordial)
        #expect(PetState.Intimacy(value: 909) == .cordial)
        #expect(PetState.Intimacy(value: 910) == .loyal)
        #expect(PetState.Intimacy(value: 1000) == .loyal)
    }

    @Test func hungerAndIntimacyUpdatesApplyToAnActivePet() {
        var pet = activePet()

        pet.applyStateChange(type: 2, objectID: 77, value: 95)
        pet.applyStateChange(type: 1, objectID: 77, value: 600)

        #expect(pet.hunger == 95)
        #expect(pet.hungerLevel == .stuffed)
        #expect(pet.intimacy == 600)
        #expect(pet.intimacyLevel == .neutral)
    }

    @Test func updatesBeforeTheStatusAreIgnored() {
        var pet = PetState()

        pet.applyStateChange(type: 2, objectID: 77, value: 95)
        pet.applyStateChange(type: 1, objectID: 77, value: 600)

        #expect(pet.hunger == 0)
        #expect(pet.intimacy == 0)
        #expect(pet.isActive == false)
    }

    @Test func initializeRecordsTheObjectID() {
        var pet = PetState()

        pet.applyStateChange(type: 0, objectID: 77, value: 0)
        #expect(pet.objectID == 77)

        pet.applyProperties(
            name: "Poring", isRenamed: false, level: 1, hunger: 50, intimacy: 100, accessoryItemID: 0, classID: 1002
        )
        // The same object again keeps the status.
        pet.applyStateChange(type: 0, objectID: 77, value: 0)
        #expect(pet.isActive)
        #expect(pet.name == "Poring")
    }

    @Test func initializeWithAnotherObjectStartsOver() {
        var pet = activePet()
        pet.applyStateChange(type: 0, objectID: 77, value: 0)

        pet.applyStateChange(type: 0, objectID: 88, value: 0)

        #expect(pet.objectID == 88)
        #expect(pet.isActive == false)
        #expect(pet.name == "")
    }

    @Test func accessoryChangeOfOwnPetAsksForNewInformation() {
        var pet = activePet()
        pet.applyStateChange(type: 0, objectID: 77, value: 0)

        let effect = pet.applyStateChange(type: 3, objectID: 77, value: 15)
        #expect(effect == .refreshInformation)
    }

    @Test func accessoryChangeOfSomeoneElsesPetIsIgnored() {
        var pet = activePet()
        pet.applyStateChange(type: 0, objectID: 77, value: 0)

        let effect = pet.applyStateChange(type: 3, objectID: 99, value: 15)
        #expect(effect == .none)
    }

    @Test func accessoryChangeWithoutKnownObjectIsIgnored() {
        var pet = activePet()

        let effect = pet.applyStateChange(type: 3, objectID: 77, value: 15)
        #expect(effect == .none)
    }

    @Test func updateEggClosesTheEggSelection() {
        var pet = PetState()

        let effect = pet.applyStateChange(type: 6, objectID: 77, value: 1)
        #expect(effect == .closeEggSelection)
    }

    @Test func performanceHairstyleAndUnknownTypesChangeNothing() {
        var pet = activePet()
        let before = pet

        let performance = pet.applyStateChange(type: 4, objectID: 77, value: 2)
        let hairstyle = pet.applyStateChange(type: 5, objectID: 77, value: 1)
        let unknown = pet.applyStateChange(type: 42, objectID: 77, value: 1)
        #expect(performance == .none)
        #expect(hairstyle == .none)
        #expect(unknown == .none)
        #expect(pet == before)
    }

    @Test func vanishOfThePetClearsIt() {
        var pet = activePet()
        pet.applyStateChange(type: 0, objectID: 77, value: 0)

        let otherVanished = pet.petVanished(objectID: 99)
        #expect(otherVanished == false)
        #expect(pet.isActive)

        let ownVanished = pet.petVanished(objectID: 77)
        #expect(ownVanished)
        #expect(pet.isActive == false)
        #expect(pet.objectID == nil)
        #expect(pet.name == "")
    }

    @Test func autoFeedFollowsTheServer() {
        var pet = activePet()
        #expect(pet.isAutoFeedEnabled == false)

        pet.setAutoFeedEnabled(true)
        #expect(pet.isAutoFeedEnabled)

        pet.reset()
        #expect(pet.isAutoFeedEnabled == false)
    }
}

struct CompanionNameTests {
    @Test func trimsWhitespace() {
        #expect(CompanionName.validated("  Poring \n") == "Poring")
    }

    @Test func rejectsEmptyNames() {
        #expect(CompanionName.validated("") == nil)
        #expect(CompanionName.validated("   ") == nil)
    }

    @Test func limitsTheNameToTheFieldSize() {
        #expect(CompanionName.validated(String(repeating: "a", count: 23)) != nil)
        #expect(CompanionName.validated(String(repeating: "a", count: 24)) == nil)
        // Two bytes per character.
        #expect(CompanionName.validated(String(repeating: "é", count: 12)) == nil)
    }

    @Test func rejectsControlCharacters() {
        #expect(CompanionName.validated("Po\u{01}ring") == nil)
        #expect(CompanionName.validated("Po\u{7f}ring") == nil)
        #expect(CompanionName.validated("Po ring") == "Po ring")
    }
}
