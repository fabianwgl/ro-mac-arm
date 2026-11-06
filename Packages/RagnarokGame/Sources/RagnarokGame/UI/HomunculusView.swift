//
//  HomunculusView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokConstants
import SwiftUI

private enum HomunculusTab: CaseIterable {
    case information
    case skills
}

/// The homunculus window: status, commands, rename, auto feed and the read-only skill list.
struct HomunculusView: View {
    var homunculus: HomunculusState
    var onClose: () -> Void = {}

    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    @State private var tab: HomunculusTab = .information
    @State private var newName = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        GameWindow {
            if homunculus.isPresent {
                HStack(alignment: .top, spacing: 0) {
                    GameVerticalTabBar(tabs: HomunculusTab.allCases, selection: $tab) { tab in
                        switch tab {
                        case .information:
                            Text(verbatim: "Info")
                        case .skills:
                            Text(verbatim: "Skills")
                        }
                    }

                    switch tab {
                    case .information:
                        information
                    case .skills:
                        skills
                    }
                }
            } else {
                emptyState
            }
        } bottomBar: {
            GameBottomBar {
                if homunculus.isPresent {
                    Button {
                        playSession.setHomunculusAutoFeed(!homunculus.isAutoFeedEnabled)
                    } label: {
                        Text(verbatim: "Auto feed: \(homunculus.isAutoFeedEnabled ? "On" : "Off")")
                    }
                    .buttonStyle(.game)
                    .frame(width: 96, height: 20)
                }
            }
        }
        .gameWindowTitle(Text(verbatim: "Homunculus"))
        .gameWindowCloseAction(onClose)
        .frame(width: 360)
    }

    // MARK: - Information

    private var information: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            meters
            stats

            if homunculus.canRename {
                CompanionRenameForm(name: $newName) {
                    playSession.renameHomunculus(to: newName)
                    newName = ""
                }
            }

            commandRow

            if isConfirmingDelete {
                deleteConfirmation
            }
        }
        .padding(5)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(verbatim: homunculus.name)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Text(verbatim: homunculus.condition.title)
                .font(.game(size: 10))
                .foregroundStyle(homunculus.condition == .active ? Color.gameProminentLabel : Color.red)

            Spacer(minLength: 0)

            Text(verbatim: "Lv \(homunculus.properties.level)")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
        }
        .padding(5)
        .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9568627451, blue: 0.9411764706, alpha: 1)))
    }

    private var meters: some View {
        let properties = homunculus.properties

        return VStack(alignment: .leading, spacing: 4) {
            CompanionMeterRow(
                title: "HP",
                fraction: homunculus.hpFraction,
                color: .green,
                detail: "\(properties.hp)/\(properties.maxHP)"
            )
            CompanionMeterRow(
                title: "SP",
                fraction: homunculus.spFraction,
                color: .blue,
                detail: "\(properties.sp)/\(properties.maxSP)"
            )
            CompanionMeterRow(
                title: "Exp",
                fraction: homunculus.expFraction,
                color: .yellow,
                detail: homunculus.isAtMaxLevel ? "Max level" : "\(properties.exp)/\(properties.expNext)"
            )
            CompanionMeterRow(
                title: "Hunger",
                fraction: homunculus.hungerFraction,
                color: .orange,
                detail: "\(homunculus.hungerLevel.title) (\(properties.hunger)/\(HomunculusState.maxHunger))"
            )
            CompanionMeterRow(
                title: "Intimacy",
                fraction: homunculus.intimacyFraction,
                color: .pink,
                detail: "\(homunculus.intimacyLevel.title) (\(properties.intimacy)/\(HomunculusState.maxIntimacy))"
            )
        }
        .padding(.horizontal, 5)
    }

    private var stats: some View {
        let properties = homunculus.properties

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HomunculusStatRow("Atk", value: properties.atk)
                HomunculusStatRow("Matk", value: properties.matk)
                HomunculusStatRow("Hit", value: properties.hit)
                HomunculusStatRow("Critical", value: properties.critical)
            }

            VStack(alignment: .leading, spacing: 3) {
                HomunculusStatRow("Def", value: properties.def)
                HomunculusStatRow("Mdef", value: properties.mdef)
                HomunculusStatRow("Flee", value: properties.flee)
                HomunculusStatRow("Aspd", value: (2000 - properties.attackMotion) / 10)
            }

            VStack(alignment: .leading, spacing: 3) {
                HomunculusStatRow("Range", value: properties.attackRange)
                HomunculusStatRow("Skill pts", value: properties.skillPoints)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
    }

    private var commandRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Button {
                    playSession.feedHomunculus()
                } label: {
                    Text(verbatim: "Feed")
                }
                .buttonStyle(.game)
                .frame(width: 46, height: 20)
                .disabled(!homunculus.isActive)

                Button {
                    playSession.moveHomunculusToOwner()
                } label: {
                    Text(verbatim: "Come here")
                }
                .buttonStyle(.game)
                .frame(width: 74, height: 20)
                .disabled(!homunculus.isActive)

                Button {
                    isConfirmingDelete = true
                } label: {
                    Text(verbatim: "Delete")
                }
                .buttonStyle(.game)
                .frame(width: 50, height: 20)
                .disabled(!homunculus.isActive)

                Spacer(minLength: 0)
            }

            // Calling, vaporizing and resurrecting are skills of the player.
            HStack(spacing: 5) {
                Button {
                    playSession.useHomunculusSkill(.am_callhomun)
                } label: {
                    Text(verbatim: "Call")
                }
                .buttonStyle(.game)
                .frame(width: 46, height: 20)
                .disabled(homunculus.condition != .vaporized || !playSession.canUseHomunculusSkill(.am_callhomun))

                Button {
                    playSession.useHomunculusSkill(.am_rest)
                } label: {
                    Text(verbatim: "Vaporize")
                }
                .buttonStyle(.game)
                .frame(width: 62, height: 20)
                .disabled(homunculus.condition != .active || !playSession.canUseHomunculusSkill(.am_rest))

                Button {
                    playSession.useHomunculusSkill(.am_resurrecthomun)
                } label: {
                    Text(verbatim: "Resurrect")
                }
                .buttonStyle(.game)
                .frame(width: 62, height: 20)
                .disabled(homunculus.condition != .dead || !playSession.canUseHomunculusSkill(.am_resurrecthomun))

                Spacer(minLength: 0)
            }
        }
    }

    private var deleteConfirmation: some View {
        HStack(spacing: 5) {
            Text(verbatim: "Delete \(homunculus.name) for good?")
                .font(.game(size: 11))
                .foregroundStyle(Color.red)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                isConfirmingDelete = false
                playSession.deleteHomunculus()
            } label: {
                Text(verbatim: "Yes")
            }
            .buttonStyle(.game)
            .frame(width: 38, height: 20)

            Button {
                isConfirmingDelete = false
            } label: {
                Text(verbatim: "No")
            }
            .buttonStyle(.game)
            .frame(width: 38, height: 20)
        }
        .padding(5)
        .background(Color(#colorLiteral(red: 1, green: 0.93, blue: 0.93, alpha: 1)))
    }

    // MARK: - Skills

    private var skills: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if homunculus.skills.isEmpty {
                    Text(verbatim: "No skills.")
                        .font(.game(size: 11))
                        .foregroundStyle(Color.gameProminentLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }

                ForEach(homunculus.skills) { skill in
                    HomunculusSkillRow(skill: skill)
                }
            }
        }
        .frame(height: 260)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "You have no homunculus.")
                .font(.game())
                .foregroundStyle(Color.gameLabel)

            if playSession.canUseHomunculusSkill(.am_callhomun) {
                Text(verbatim: "Use Call Homunculus with an embryo to create one.")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)

                Button {
                    playSession.useHomunculusSkill(.am_callhomun)
                } label: {
                    Text(verbatim: "Call")
                }
                .buttonStyle(.game)
                .frame(width: 46, height: 20)
            } else {
                Text(verbatim: "Alchemists create one with the Call Homunculus skill.")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}

private struct HomunculusStatRow: View {
    var title: String
    var value: Int

    init(_ title: String, value: Int) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: title)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)

            Text(verbatim: "\(value)")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameLabel)
        }
    }
}

private struct HomunculusSkillRow: View {
    var skill: HomunculusState.Skill

    @Environment(GameContext.self) private var gameContext

    private var skillName: String {
        if let name = gameContext.skillInfoTable.localizedSkillName(forSkillID: skill.id) {
            name
        } else if let skillID = SkillID(rawValue: skill.id) {
            skillID.stringValue
        } else if !skill.identifier.isEmpty {
            skill.identifier
        } else {
            "Skill \(skill.id)"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: skillName)
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .lineLimit(1)

                Text(verbatim: "Lv: \(skill.level)")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: skill.spCost > 0 ? "SP: \(skill.spCost)" : "Passive")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameLabel)
        }
        .padding(.leading, 15)
        .padding(.trailing, 8)
        .frame(height: 36)
    }
}

#Preview {
    let homunculus: HomunculusState = {
        var homunculus = HomunculusState()
        homunculus.apply(HomunculusState.Properties(
            name: "Lif",
            isRenamed: false,
            isVaporized: false,
            isAlive: true,
            level: 12,
            hunger: 70,
            intimacy: 320,
            atk: 80,
            matk: 40,
            hit: 90,
            critical: 4,
            def: 20,
            mdef: 10,
            flee: 55,
            attackMotion: 700,
            hp: 900,
            maxHP: 1200,
            sp: 50,
            maxSP: 80,
            exp: 4000,
            expNext: 10000,
            skillPoints: 2,
            attackRange: 1
        ))
        return homunculus
    }()

    HomunculusView(homunculus: homunculus)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
