//
//  SkillEffectTable.swift
//  RagnarokEffects
//
//  Created by Leon Li on 2026/4/30.
//

import Foundation
import RagnarokConstants

// Ported from roBrowserLegacy:
// https://github.com/MrAntares/roBrowserLegacy/blob/master/src/DB/Skills/SkillEffect.js
public enum SkillEffectTable {
    // Keep entries sorted in ascending order by `SkillID.rawValue`.
    private static let table: [SkillID : SkillEffectDefinition] = [
        .sm_bash: .init(
            beginCastEffects: [.id(.ef_bash)],
            hitEffects: [.id(.ef_hit2)]
        ),
        .sm_provoke: .init(
            successEffects: [.id(.ef_provoke)]
        ),
        .sm_endure: .init(
            effects: [.id(.ef_endure)]
        ),
        .mg_napalmbeat: .init(
            hitEffects: [.id(.ef_hit2)]
        ),
        .mg_safetywall: .init(
            effects: [.id(.ef_glasswall2)]
        ),
        .mg_soulstrike: .init(
            beforeHitEffects: [.id(.ef_soulstrike)],
            hitEffects: [.id(.ef_hit2)]
        ),
        .mg_coldbolt: .init(
            beforeHitEffects: [.name("ef_coldbolt")],
            hitEffects: [.id(.ef_coldhit)]
        ),
        .mg_frostdiver: .init(
            effects: [.id(.ef_frostdiver)],
            hitEffects: [.id(.ef_frostdiver2)]
        ),
        .mg_stonecurse: .init(
            effects: [.id(.ef_stonecurse)]
        ),
        .mg_fireball: .init(
            beforeHitEffects: [.id(.ef_fireball)],
            hitEffects: [.id(.ef_firehit)]
        ),
        .mg_firewall: .init(
            hitEffects: [.id(.ef_firehit)],
            groundEffects: [.id(.ef_firewall)]
        ),
        .mg_firebolt: .init(
            beforeHitEffects: [.name("ef_firebolt")],
            hitEffects: [.id(.ef_firehit)]
        ),
        .mg_lightningbolt: .init(
            effects: [.id(.ef_lightbolt)],
            hitEffects: [.id(.ef_windhit)]
        ),
        .mg_thunderstorm: .init(
            effects: [.id(.ef_thunderstorm)],
            hitEffects: [.id(.ef_windhit)]
        ),
        .al_pneuma: .init(
            groundEffects: [.id(.ef_pneuma)]
        ),
        .al_heal: .init(
            effects: [.id(.ef_heal)],
            hitEffects: [.id(.ef_heal3)]
        ),
        .al_incagi: .init(
            effects: [.id(.ef_incagility)]
        ),
        .al_decagi: .init(
            effects: [.id(.ef_decagility)]
        ),
        .al_holywater: .init(
            effects: [.id(.ef_aqua)]
        ),
        .al_crucis: .init(
            effects: [.id(.ef_signum)]
        ),
        .al_angelus: .init(
            effects: [.id(.ef_angelus)]
        ),
        .al_blessing: .init(
            effects: [.id(.ef_blessing)]
        ),
        .al_cure: .init(
            effects: [.id(.ef_cure)]
        ),
        .mc_mammonite: .init(
            effects: [.id(.ef_coin)]
        ),
        .ac_concentration: .init(
            effects: [.id(.ef_concentration)]
        ),
        .ac_double: .init(
            beginCastEffects: [.id(.ef_bash)],
            beforeHitEffects: [.name("ef_arrow_projectile")],
            hitEffects: [.id(.ef_hit2)]
        ),
        .ac_shower: .init(
            effects: [.name("ef_arrow_shower_projectile")],
            hitEffects: [.id(.ef_hit2)]
        ),
        .tf_poison: .init(
            effects: [.id(.ef_invenom)]
        ),
        .all_resurrection: .init(
            effects: [.id(.ef_resurrection), .id(.ef_revive)]
        ),
        .kn_pierce: .init(
            effects: [.id(.ef_pierceself)]
        ),
        .kn_brandishspear: .init(
            effects: [.id(.ef_brandish2)]
        ),
        .kn_spearstab: .init(
            effects: [.id(.ef_spearstabself)]
        ),
        .kn_spearboomerang: .init(
            effects: [.id(.ef_spearbmrself)]
        ),
        .kn_twohandquicken: .init(
            effects: [.id(.ef_twohandquicken)]
        ),
        .kn_autocounter: .init(
            effects: [.id(.ef_autocounter)]
        ),
        .kn_bowlingbash: .init(
            effects: [.id(.ef_bowlingself)]
        ),
        .pr_impositio: .init(
            effects: [.id(.ef_impositio)]
        ),
        .pr_suffragium: .init(
            effects: [.id(.ef_suffragium)]
        ),
        .pr_aspersio: .init(
            effects: [.id(.ef_aspersio)]
        ),
        .pr_benedictio: .init(
            effects: [.id(.ef_benedictio)]
        ),
        .pr_sanctuary: .init(
            effects: [.id(.ef_sanctuary)]
        ),
        .pr_slowpoison: .init(
            effects: [.id(.ef_slowpoison)]
        ),
        .pr_strecovery: .init(
            effects: [.id(.ef_recovery)]
        ),
        .pr_kyrie: .init(
            effects: [.id(.ef_kyrie)]
        ),
        .pr_magnificat: .init(
            effects: [.id(.ef_magnificat)]
        ),
        .pr_gloria: .init(
            effects: [.id(.ef_gloria)]
        ),
        .pr_lexdivina: .init(
            effects: [.id(.ef_lexdivina)]
        ),
        .pr_turnundead: .init(
            effects: [.id(.ef_holyhit)]
        ),
        .pr_lexaeterna: .init(
            effects: [.id(.ef_lexaeterna)]
        ),
        .pr_magnus: .init(
            effects: [.id(.ef_magnus)],
            hitEffects: [.id(.ef_holyhit)]
        ),
        .wz_meteor: .init(
            effects: [.id(.ef_meteorstorm)],
            hitEffects: [.id(.ef_firehit)]
        ),
        .wz_vermilion: .init(
            effects: [.id(.ef_lord)],
            hitEffects: [.id(.ef_windhit)]
        ),
        .wz_stormgust: .init(
            effects: [.id(.ef_stormgust)]
        ),
        .wz_quagmire: .init(
            groundEffects: [.id(.ef_quagmire)]
        ),
        .bs_repairweapon: .init(
            effects: [.id(.ef_repairweapon)]
        ),
        .bs_hammerfall: .init(
            effects: [.id(.ef_crashearth)]
        ),
        .bs_weaponperfect: .init(
            effects: [.id(.ef_perfection)]
        ),
        .bs_maximize: .init(
            effects: [.id(.ef_maxpower)]
        ),
        .ht_springtrap: .init(
            effects: [.id(.ef_springtrap)]
        ),
        .as_sonicblow: .init(
            effects: [.id(.ef_sonicblow2)]
        ),
        .as_poisonreact: .init(
            effects: [.id(.ef_poisonreact)]
        ),
        .as_venomdust: .init(
            effects: [.id(.ef_venomdust)]
        ),
        .as_splasher: .init(
            effects: [.id(.ef_splasher)]
        ),
        .mc_cartrevolution: .init(
            effects: [.id(.ef_cartrevolution)]
        ),
        .mc_loud: .init(
            effects: [.id(.ef_loud)]
        ),
        .al_holylight: .init(
            effects: [.id(.ef_holyhit)]
        ),
        .mg_energycoat: .init(
            effects: [.id(.ef_energycoat)]
        ),
        .rg_stealcoin: .init(
            effects: [.id(.ef_stealcoin)]
        ),
        .rg_stripweapon: .init(
            effects: [.id(.ef_stripweapon)]
        ),
        .rg_stripshield: .init(
            effects: [.id(.ef_stripshield)]
        ),
        .rg_striparmor: .init(
            effects: [.id(.ef_striparmor)]
        ),
        .rg_striphelm: .init(
            effects: [.id(.ef_striphelm)]
        ),
        .cr_shieldcharge: .init(
            effects: [.id(.ef_shieldcharge)]
        ),
        .cr_holycross: .init(
            effects: [.id(.ef_holycross)]
        ),
        .cr_devotion: .init(
            effects: [.id(.ef_devotion)]
        ),
        .cr_providence: .init(
            effects: [.id(.ef_providence)]
        ),
        .cr_spearquicken: .init(
            effects: [.id(.ef_twohandquicken)]
        ),
        .mo_chaincombo: .init(
            effects: [.id(.ef_chaincombo)]
        ),
        .sa_magicrod: .init(
            effects: [.id(.ef_magicrod)]
        ),
        .sa_spellbreaker: .init(
            effects: [.id(.ef_spellbreaker)]
        ),
        .sa_flamelauncher: .init(
            effects: [.id(.ef_flamelauncher)]
        ),
        .sa_frostweapon: .init(
            effects: [.id(.ef_frostweapon)]
        ),
        .sa_lightningloader: .init(
            effects: [.id(.ef_lightningloader)]
        ),
        .sa_seismicweapon: .init(
            effects: [.id(.ef_seismicweapon)]
        ),
        .sa_dispell: .init(
            effects: [.id(.ef_dispell)]
        ),
        .hp_assumptio: .init(
            effects: [.id(.ef_assumptio2)]
        ),
        .ws_meltdown: .init(
            effects: [.id(.ef_meltdown)]
        ),
        .ws_cartboost: .init(
            effects: [.id(.ef_cartboost)]
        ),
        .st_rejectsword: .init(
            effects: [.id(.ef_rejectsword)]
        ),
    ]

    public static func beginCastEffects(for skillID: SkillID) -> [EffectReference] {
        table[skillID]?.beginCastEffects ?? []
    }

    public static func effects(for skillID: SkillID) -> [EffectReference] {
        table[skillID]?.effects ?? []
    }

    public static func beforeHitEffects(for skillID: SkillID) -> [EffectReference] {
        table[skillID]?.beforeHitEffects ?? []
    }

    public static func hitEffects(for skillID: SkillID) -> [EffectReference] {
        table[skillID]?.hitEffects ?? []
    }

    public static func successEffects(for skillID: SkillID) -> [EffectReference] {
        table[skillID]?.successEffects ?? []
    }

    public static func groundEffects(for skillID: SkillID) -> [EffectReference] {
        table[skillID]?.groundEffects ?? []
    }

    public static var skillIDs: [SkillID] {
        table.keys.sorted(using: KeyPathComparator(\.rawValue))
    }
}
