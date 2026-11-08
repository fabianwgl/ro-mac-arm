import RagnarokConstants
import Testing
@testable import RagnarokEffects

private func references(of skillID: SkillID) -> [EffectReference] {
    SkillEffectTable.beginCastEffects(for: skillID)
        + SkillEffectTable.effects(for: skillID)
        + SkillEffectTable.beforeHitEffects(for: skillID)
        + SkillEffectTable.hitEffects(for: skillID)
        + SkillEffectTable.successEffects(for: skillID)
        + SkillEffectTable.groundEffects(for: skillID)
}

/// What a definition draws or plays, for readable assertions.
private func kind(of definition: EffectDefinition) -> String {
    switch definition {
    case .`2D`: "2D"
    case .`3D`: "3D"
    case .cylinder: "cylinder"
    case .spr: "spr"
    case .str: "str"
    case .wav: "wav"
    }
}

/// References that the table keeps on purpose even though no definition exists yet.
private let knownUndefinedReferences: Set<String> = [
    // "The ice traveling to the target has no definition yet." (EffectTable.swift)
    "ef_frostdiver",
]

@Test func everySkillEffectReferenceResolvesToDefinitions() {
    var unresolved: [String] = []
    for skillID in SkillEffectTable.skillIDs {
        for reference in references(of: skillID) {
            let name = reference.description
            if knownUndefinedReferences.contains(name) {
                continue
            }
            if EffectTable.definitions(for: reference).isEmpty {
                unresolved.append("\(skillID) -> \(name)")
            }
        }
    }
    #expect(unresolved.isEmpty, "skill effects without a definition: \(unresolved)")
}

@Test func handWrittenEffectsAreNotShadowedByTheReferenceTable() {
    let hand = Set(EffectTable.table.keys)
    let reference = Set(EffectTable.referenceTable.keys)
    #expect(hand.isDisjoint(with: reference), "defined twice: \(hand.intersection(reference))")
    #expect(EffectTable.effectIDs.count == hand.count + reference.count)
}

@Test func referenceTableUsesWellFormedFileNames() {
    for (effectID, definitions) in EffectTable.referenceTable {
        for definition in definitions {
            switch definition {
            case .str(let str):
                #expect(str.fileName.hasSuffix(".str"), "\(effectID): \(str.fileName)")
                #expect(!str.fileName.contains("%d") || str.randomNumberRange != nil, "\(effectID): \(str.fileName)")
                if let sound = str.soundName {
                    #expect(sound.hasSuffix(".wav"), "\(effectID): \(sound)")
                }
            case .wav(let wav):
                #expect(wav.soundName.hasSuffix(".wav"), "\(effectID): \(wav.soundName)")
                #expect(!wav.soundName.contains("%d") || wav.randomNumberRange != nil, "\(effectID): \(wav.soundName)")
            case .spr(let spr):
                #expect(!spr.fileName.isEmpty && !spr.fileName.hasSuffix(".spr"), "\(effectID): \(spr.fileName)")
            default:
                Issue.record("\(effectID): the reference table only holds STR, SPR and WAV definitions")
            }
        }
    }
}

@Test func priestBuffsPlayTheirStrEffectOnTheTarget() throws {
    let effects = SkillEffectTable.effects(for: .pr_kyrie)
    #expect(effects.map(\.description) == ["ef_kyrie"])

    let definitions = EffectTable.definitions(for: try #require(effects.first))
    #expect(definitions.map(kind(of:)) == ["str"])
    guard case .str(let str) = definitions[0] else {
        Issue.record("expected an STR definition")
        return
    }
    #expect(str.fileName == "kyrie.str")
    #expect(str.attachedToTarget)
}

@Test func numberedStrVariantsKeepTheirRandomRange() throws {
    // Fire Wall and Pneuma pick one of several numbered files each time they are drawn.
    let firewall = EffectTable.definitions(for: .ef_firewall)
    guard case .str(let wall) = try #require(firewall.first) else {
        Issue.record("expected an STR definition")
        return
    }
    #expect(wall.fileName == "firewall%d.str")
    #expect(wall.randomNumberRange == 1...2)

    let pneuma = EffectTable.definitions(for: .ef_pneuma)
    guard case .str(let shield) = try #require(pneuma.first) else {
        Issue.record("expected an STR definition")
        return
    }
    #expect(shield.fileName == "pneuma%d.str")
    #expect(shield.randomNumberRange == 1...3)
    #expect(!shield.attachedToTarget)
}

@Test func groundUnitEffectsAreKeptApartFromCastEffects() {
    #expect(SkillEffectTable.groundEffects(for: .mg_firewall).map(\.description) == ["ef_firewall"])
    #expect(SkillEffectTable.groundEffects(for: .al_pneuma).map(\.description) == ["ef_pneuma"])
    #expect(SkillEffectTable.groundEffects(for: .wz_quagmire).map(\.description) == ["ef_quagmire"])

    // A ground unit effect must not also play when the skill is cast.
    #expect(SkillEffectTable.effects(for: .mg_firewall).isEmpty)
    #expect(SkillEffectTable.effects(for: .al_pneuma).isEmpty)
    #expect(SkillEffectTable.effects(for: .wz_quagmire).isEmpty)
}

@Test func skillsOfEveryFirstAndSecondJobFamilyHaveAnEffect() {
    let skills: [SkillID] = [
        // Swordman and Knight
        .sm_provoke, .sm_endure, .kn_pierce, .kn_brandishspear, .kn_spearstab, .kn_spearboomerang,
        .kn_twohandquicken, .kn_autocounter, .kn_bowlingbash,
        // Mage, Wizard and Sage
        .mg_safetywall, .mg_stonecurse, .mg_firewall, .mg_energycoat, .wz_meteor, .wz_vermilion,
        .wz_stormgust, .wz_quagmire, .sa_spellbreaker, .sa_dispell, .sa_magicrod, .sa_flamelauncher,
        // Acolyte and Priest
        .al_pneuma, .al_holylight, .pr_impositio, .pr_suffragium, .pr_aspersio, .pr_benedictio,
        .pr_sanctuary, .pr_kyrie, .pr_magnificat, .pr_gloria, .pr_lexdivina, .pr_turnundead,
        .pr_lexaeterna, .pr_magnus,
        // Merchant and Blacksmith
        .mc_mammonite, .mc_cartrevolution, .mc_loud, .bs_hammerfall, .bs_weaponperfect, .bs_maximize,
        // Thief, Assassin and Rogue
        .tf_poison, .as_sonicblow, .as_poisonreact, .as_venomdust, .as_splasher, .rg_stealcoin,
        .rg_stripweapon, .rg_stripshield, .rg_striparmor, .rg_striphelm,
        // Hunter, Crusader and Monk
        .ht_springtrap, .cr_shieldcharge, .cr_holycross, .cr_devotion, .cr_providence, .cr_spearquicken,
        .mo_chaincombo,
    ]
    for skillID in skills {
        #expect(!references(of: skillID).isEmpty, "\(skillID) has no skill effect")
    }
}

@Test func spearQuickenAndTwoHandQuickenShareTheirEffect() {
    #expect(SkillEffectTable.effects(for: .cr_spearquicken).map(\.description) == ["ef_twohandquicken"])
    #expect(SkillEffectTable.effects(for: .kn_twohandquicken).map(\.description) == ["ef_twohandquicken"])
}

@Test func skillIDsAreListedInAscendingOrder() {
    let ids = SkillEffectTable.skillIDs.map(\.rawValue)
    #expect(ids == ids.sorted())
    #expect(ids.count == Set(ids).count)
}
