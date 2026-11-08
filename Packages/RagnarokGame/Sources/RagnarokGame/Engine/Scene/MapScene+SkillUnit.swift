//
//  MapScene+SkillUnit.swift
//  RagnarokGame
//

import Foundation
import QuartzCore
import RagnarokEffects
import simd

// Skill units are the cells that skills leave on the ground: Fire Wall, Pneuma, Quagmire,
// traps, songs. The server announces each cell with `ZC_SKILL_ENTRY*` and removes it with
// `ZC_SKILL_DISAPPEAR`. Only units whose skill has ground effects get a picture.
extension MapScene {
    /// How long a unit effect is kept when the server never removes the unit, for example when
    /// the player walks out of sight. Unit effects loop until then.
    private static let skillUnitEffectLifetime: TimeInterval = 600

    public func onSkillUnitSpawned(unitID: GameObjectID, unitTypeID: Int, position: SIMD2<Int>) {
        let references = SkillUnitTable.groundEffects(forUnitID: unitTypeID)
        guard !references.isEmpty, mapGrid.contains(position) else {
            return
        }

        // The server sends the unit again when it comes back into sight.
        onSkillUnitVanished(unitID: unitID)

        let currentTime = CACurrentMediaTime()
        for reference in references {
            let effect = MapSceneEffect(
                reference: reference,
                creationTime: currentTime,
                gridPosition: position,
                targetObjectID: nil,
                ownerObjectID: nil,
                skillUnitID: unitID,
                duration: Self.skillUnitEffectLifetime
            )
            effects[effect.id] = effect
        }
    }

    public func onSkillUnitVanished(unitID: GameObjectID) {
        let unitEffectIDs = effects.compactMap { effectID, effect in
            effect.skillUnitID == unitID ? effectID : nil
        }
        for effectID in unitEffectIDs {
            removeEffect(objectID: effectID)
        }
    }
}
