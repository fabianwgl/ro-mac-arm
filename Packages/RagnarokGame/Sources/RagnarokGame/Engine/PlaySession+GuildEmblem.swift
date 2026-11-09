//
//  PlaySession+GuildEmblem.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import CoreGraphics
import Foundation
import RagnarokCore
import RagnarokNetwork
import RagnarokPackets

extension PlaySession {
    /// Asks for the emblem of a guild unless that version is cached or already asked for.
    ///
    /// `version` is the emblem id the server reported for the guild (`ZC_UPDATE_GDID`, `ZC_GUILD_INFO`,
    /// `ZC_CHANGE_GUILD`); 0 means the guild has no emblem. Pass `nil` for a guild whose version is unknown, such as
    /// an allied guild: it is asked for once. The answer is `ZC_GUILD_EMBLEM_IMG` (0x152). rAthena sends nothing for a
    /// guild it has not loaded or that has no emblem.
    func requestGuildEmblemIfNeeded(guildID: UInt32, version: Int?) {
        guard guildID != 0 else {
            return
        }

        if let version {
            let version = UInt32(truncatingIfNeeded: version)
            guard version > 0,
                  guildState.emblems[guildID]?.version != version,
                  guildState.requestedEmblems[guildID] != version else {
                return
            }
            guildState.requestedEmblems[guildID] = version
        } else {
            guard guildState.emblems[guildID] == nil, guildState.requestedEmblems[guildID] == nil else {
                return
            }
            guildState.requestedEmblems[guildID] = 0
        }

        sendPacket(PacketFactory.CZ_REQ_GUILD_EMBLEM_IMG(guildID: guildID))
    }

    /// `ZC_GUILD_EMBLEM_IMG`, sent for a request and, unasked, to every online member when the master changes it.
    func handleGuildEmblem(_ packet: PACKET_ZC_GUILD_EMBLEM_IMG_LEGACY) {
        guard let image = GuildEmblemCodec.decode(packet.data) else {
            return
        }

        guildState.emblems[packet.guildID] = GuildEmblem(version: packet.emblemID, image: image)
    }

    /// Master only. Takes the bytes of an image file (BMP, GIF, PNG, anything ImageIO reads), shrinks it to 24 by 24
    /// and uploads it. The server answers with the new emblem for the whole guild.
    func changeGuildEmblem(fromImageData data: Data) {
        guard guildState.guild.isInGuild else {
            return
        }
        guard guildState.guild.isMaster else {
            addGuildMessage("Only the guild master can change the emblem.", type: .error)
            return
        }
        guard let image = CGImageCreateWithData(data), let emblem = GuildEmblemCodec.encode(image) else {
            addGuildMessage("That file is not an image the emblem can be made from.", type: .error)
            return
        }

        sendPacket(PacketFactory.CZ_REGISTER_GUILD_EMBLEM_IMG(data: emblem))
    }
}
