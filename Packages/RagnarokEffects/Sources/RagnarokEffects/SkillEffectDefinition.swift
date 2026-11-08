//
//  SkillEffectDefinition.swift
//  RagnarokEffects
//
//  Created by Leon Li on 2026/4/30.
//

struct SkillEffectDefinition: Sendable {
    var beginCastEffects: [EffectReference] = []
    var effects: [EffectReference] = []
    var beforeHitEffects: [EffectReference] = []
    var hitEffects: [EffectReference] = []
    var successEffects: [EffectReference] = []

    /// Effects of the skill's ground unit (Fire Wall, Pneuma, Quagmire), which stay on the
    /// cell for as long as the unit exists. The client plays them on `ZC_SKILL_ENTRY*`.
    var groundEffects: [EffectReference] = []
}
