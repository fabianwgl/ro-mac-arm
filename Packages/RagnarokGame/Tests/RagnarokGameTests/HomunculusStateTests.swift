//
//  HomunculusStateTests.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokGame

struct HomunculusStateTests {
    private func properties(
        name: String = "Lif",
        isRenamed: Bool = false,
        isVaporized: Bool = false,
        isAlive: Bool = true,
        hunger: Int = 70,
        intimacy: Int = 320,
        hp: Int = 900,
        exp: Int64 = 4000,
        expNext: Int64 = 10000
    ) -> HomunculusState.Properties {
        HomunculusState.Properties(
            name: name,
            isRenamed: isRenamed,
            isVaporized: isVaporized,
            isAlive: isAlive,
            level: 12,
            hunger: hunger,
            intimacy: intimacy,
            atk: 80,
            matk: 40,
            hit: 90,
            critical: 4,
            def: 20,
            mdef: 10,
            flee: 55,
            attackMotion: 700,
            hp: hp,
            maxHP: 1200,
            sp: 50,
            maxSP: 80,
            exp: exp,
            expNext: expNext,
            skillPoints: 2,
            attackRange: 1
        )
    }

    private func activeHomunculus() -> HomunculusState {
        var homunculus = HomunculusState()
        homunculus.apply(properties())
        return homunculus
    }

    @Test func newStateHasNoHomunculus() {
        let homunculus = HomunculusState()
        #expect(homunculus.isPresent == false)
        #expect(homunculus.isActive == false)
        #expect(homunculus.canRename == false)
        #expect(homunculus.skills.isEmpty)
    }

    @Test func applyPropertiesFillsTheStatus() {
        let homunculus = activeHomunculus()

        #expect(homunculus.isPresent)
        #expect(homunculus.isActive)
        #expect(homunculus.condition == .active)
        #expect(homunculus.name == "Lif")
        #expect(homunculus.properties.level == 12)
        #expect(homunculus.properties.maxHP == 1200)
        #expect(homunculus.hpFraction == 0.75)
        #expect(homunculus.spFraction == 0.625)
        #expect(homunculus.expFraction == 0.4)
        #expect(homunculus.isAtMaxLevel == false)
        #expect(homunculus.canRename)
    }

    @Test func flagsSelectTheCondition() {
        var homunculus = HomunculusState()

        homunculus.apply(properties(isVaporized: true, isAlive: true))
        #expect(homunculus.condition == .vaporized)
        #expect(homunculus.isPresent)
        #expect(homunculus.isActive == false)

        homunculus.apply(properties(isVaporized: false, isAlive: false, hp: 0))
        #expect(homunculus.condition == .dead)
        #expect(homunculus.isPresent)
        #expect(homunculus.isActive == false)

        homunculus.apply(properties())
        #expect(homunculus.condition == .active)
    }

    @Test func renamingNeedsAnActiveUnrenamedHomunculus() {
        var homunculus = HomunculusState()

        homunculus.apply(properties(isRenamed: true))
        #expect(homunculus.canRename == false)

        homunculus.apply(properties(isRenamed: false, isVaporized: true))
        #expect(homunculus.canRename == false)

        homunculus.apply(properties(isRenamed: false))
        #expect(homunculus.canRename)
    }

    @Test func deletedHomunculusIsCleared() {
        var homunculus = activeHomunculus()
        homunculus.setAutoFeedEnabled(true)

        // hom_delete: intimacy 0, HP 0, not vaporized.
        homunculus.apply(properties(isVaporized: false, isAlive: false, intimacy: 0, hp: 0))

        #expect(homunculus.isPresent == false)
        #expect(homunculus.name == "")
        #expect(homunculus.isAutoFeedEnabled == false)
    }

    @Test func zeroIntimacyWhileVaporizedOrAliveKeepsTheHomunculus() {
        var homunculus = HomunculusState()

        homunculus.apply(properties(isVaporized: true, isAlive: true, intimacy: 0))
        #expect(homunculus.isPresent)

        homunculus.apply(properties(isVaporized: false, isAlive: true, intimacy: 0))
        #expect(homunculus.isPresent)
    }

    @Test func maximumLevelHasNoNextExperience() {
        var homunculus = HomunculusState()
        homunculus.apply(properties(exp: 0, expNext: 0))

        #expect(homunculus.isAtMaxLevel)
        #expect(homunculus.expFraction == 0)
    }

    @Test func intimacyGradesFollowRathenaThresholds() {
        // The packet carries intimacy divided by 100, the grades start at 400, 1100, 10100, 25100, 75100 and 91100.
        #expect(HomunculusState.Intimacy(value: 0) == .hateWithPassion)
        #expect(HomunculusState.Intimacy(value: 3) == .hateWithPassion)
        #expect(HomunculusState.Intimacy(value: 4) == .hate)
        #expect(HomunculusState.Intimacy(value: 10) == .hate)
        #expect(HomunculusState.Intimacy(value: 11) == .awkward)
        #expect(HomunculusState.Intimacy(value: 100) == .awkward)
        #expect(HomunculusState.Intimacy(value: 101) == .shy)
        #expect(HomunculusState.Intimacy(value: 250) == .shy)
        #expect(HomunculusState.Intimacy(value: 251) == .neutral)
        #expect(HomunculusState.Intimacy(value: 750) == .neutral)
        #expect(HomunculusState.Intimacy(value: 751) == .cordial)
        #expect(HomunculusState.Intimacy(value: 910) == .cordial)
        #expect(HomunculusState.Intimacy(value: 911) == .loyal)
        #expect(HomunculusState.Intimacy(value: 1000) == .loyal)
    }

    @Test func parameterChangesUpdateHPSPAndExperience() {
        var homunculus = activeHomunculus()

        homunculus.applyParameterChange(type: 5, value: 300)
        homunculus.applyParameterChange(type: 7, value: 20)
        homunculus.applyParameterChange(type: 1, value: 8000)

        #expect(homunculus.properties.hp == 300)
        #expect(homunculus.properties.sp == 20)
        #expect(homunculus.properties.exp == 8000)
        #expect(homunculus.expFraction == 0.8)
        #expect(homunculus.condition == .active)
    }

    @Test func zeroHPMarksTheHomunculusDead() {
        var homunculus = activeHomunculus()

        homunculus.applyParameterChange(type: 5, value: 0)
        #expect(homunculus.condition == .dead)

        homunculus.applyParameterChange(type: 5, value: 100)
        #expect(homunculus.condition == .active)
    }

    @Test func parameterChangesBeforeTheStatusAreIgnored() {
        var homunculus = HomunculusState()

        homunculus.applyParameterChange(type: 5, value: 300)

        #expect(homunculus.isPresent == false)
        #expect(homunculus.properties.hp == 0)
    }

    @Test func unknownParameterTypesAreIgnored() {
        var homunculus = activeHomunculus()
        let before = homunculus

        homunculus.applyParameterChange(type: 99, value: 1)

        #expect(homunculus == before)
    }

    @Test func stateChangeRecordsObjectIDHungerAndIntimacy() {
        var homunculus = activeHomunculus()

        homunculus.applyStateChange(state: 0, objectID: 55, value: 0)
        homunculus.applyStateChange(state: 2, objectID: 55, value: 90)
        homunculus.applyStateChange(state: 1, objectID: 55, value: 600)

        #expect(homunculus.objectID == 55)
        #expect(homunculus.properties.hunger == 90)
        #expect(homunculus.hungerLevel == .satisfied)
        #expect(homunculus.properties.intimacy == 600)
        #expect(homunculus.intimacyLevel == .neutral)
    }

    @Test func stateChangeBeforeTheStatusOnlyRecordsTheObjectID() {
        var homunculus = HomunculusState()

        homunculus.applyStateChange(state: 0, objectID: 55, value: 0)
        homunculus.applyStateChange(state: 2, objectID: 55, value: 90)

        #expect(homunculus.objectID == 55)
        #expect(homunculus.isPresent == false)
        #expect(homunculus.properties.hunger == 0)
    }

    @Test func skillListReplacesAndUpdates() {
        var homunculus = activeHomunculus()

        homunculus.apply(skills: [
            HomunculusState.Skill(id: 8001, identifier: "HLIF_HEAL", level: 1, spCost: 13, range: 9, isUpgradable: true),
            HomunculusState.Skill(id: 8002, identifier: "HLIF_AVOID", level: 0, spCost: 20, range: 0, isUpgradable: false),
        ])
        #expect(homunculus.skills.map(\.id) == [8001, 8002])

        homunculus.updateSkill(id: 8001, level: 2, spCost: 16, range: 9, isUpgradable: false)
        #expect(homunculus.skills[0].level == 2)
        #expect(homunculus.skills[0].spCost == 16)
        #expect(homunculus.skills[0].isUpgradable == false)

        homunculus.updateSkill(id: 9999, level: 5, spCost: 1, range: 1, isUpgradable: true)
        #expect(homunculus.skills.count == 2)

        homunculus.apply(skills: [])
        #expect(homunculus.skills.isEmpty)
    }

    @Test func autoFeedFollowsTheServer() {
        var homunculus = activeHomunculus()
        #expect(homunculus.isAutoFeedEnabled == false)

        homunculus.setAutoFeedEnabled(true)
        #expect(homunculus.isAutoFeedEnabled)
    }
}
