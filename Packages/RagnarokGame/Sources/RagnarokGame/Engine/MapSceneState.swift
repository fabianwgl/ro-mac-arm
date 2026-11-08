//
//  MapSceneState.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/5/31.
//

import Observation
import RagnarokModels
import RagnarokSprite

@MainActor
@Observable
final class MapSceneState {
    var playerPosition: SIMD2<Int>
    var playerDirection: SpriteDirection
    var isPlayerDead = false

    var selectedTargetType: MapObjectType?

    /// The player that is selected, when the selected target is one. Trade requests go to this player.
    var selectedPlayer: SelectedPlayer?

    struct SelectedPlayer: Equatable {
        var accountID: UInt32
        var name: String
    }

    init(playerPosition: SIMD2<Int>, playerDirection: SpriteDirection) {
        self.playerPosition = playerPosition
        self.playerDirection = playerDirection
    }
}
