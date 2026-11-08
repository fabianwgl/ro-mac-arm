import RagnarokConstants
import Testing
@testable import RagnarokEffects

@Test func skillUnitIDsMapToTheirSkill() {
    // rAthena `e_skill_unit_id`: UNT_SAFETYWALL = 0x7e, UNT_FIREWALL, UNT_WARP_WAITING,
    // UNT_WARP_ACTIVE, UNT_BENEDICTIO, UNT_SANCTUARY, UNT_MAGNUS, UNT_PNEUMA, UNT_DUMMYSKILL.
    #expect(SkillUnitTable.skillID(forUnitID: 0x7e) == .mg_safetywall)
    #expect(SkillUnitTable.skillID(forUnitID: 0x7f) == .mg_firewall)
    #expect(SkillUnitTable.skillID(forUnitID: 0x81) == .al_warp)
    #expect(SkillUnitTable.skillID(forUnitID: 0x83) == .pr_sanctuary)
    #expect(SkillUnitTable.skillID(forUnitID: 0x84) == .pr_magnus)
    #expect(SkillUnitTable.skillID(forUnitID: 0x85) == .al_pneuma)
    #expect(SkillUnitTable.skillID(forUnitID: 0x8e) == .wz_quagmire)
    #expect(SkillUnitTable.skillID(forUnitID: 0x9e) == .bd_lullaby)
}

@Test func unitsWithoutAPictureMapToNothing() {
    // UNT_DUMMYSKILL "shows no effect on the client".
    #expect(SkillUnitTable.skillID(forUnitID: 0x86) == nil)
    #expect(SkillUnitTable.skillID(forUnitID: 0) == nil)
    #expect(SkillUnitTable.skillID(forUnitID: 0xffff) == nil)
    #expect(SkillUnitTable.groundEffects(forUnitID: 0x86).isEmpty)
}

@Test func groundUnitsDrawTheEffectOfTheirSkill() {
    #expect(SkillUnitTable.groundEffects(forUnitID: 0x7f).map(\.description) == ["ef_firewall"])
    #expect(SkillUnitTable.groundEffects(forUnitID: 0x85).map(\.description) == ["ef_pneuma"])
    #expect(SkillUnitTable.groundEffects(forUnitID: 0x8e).map(\.description) == ["ef_quagmire"])
}

@Test func unitsWhoseSkillHasNoGroundEffectDrawNothing() {
    // Known gap: the reference has no picture for these, so the unit stays invisible.
    #expect(SkillUnitTable.groundEffects(forUnitID: 0x7e).isEmpty)
    #expect(SkillUnitTable.groundEffects(forUnitID: 0x81).isEmpty)
    #expect(SkillUnitTable.groundEffects(forUnitID: 0x83).isEmpty)
}

@Test func groundUnitEffectsResolveToDefinitions() {
    for unitID in [0x7f, 0x85, 0x8e] {
        for reference in SkillUnitTable.groundEffects(forUnitID: unitID) {
            #expect(!EffectTable.definitions(for: reference).isEmpty, "unit \(unitID): \(reference)")
        }
    }
}
