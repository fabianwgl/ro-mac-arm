//
//  GuildEmblemTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import CoreGraphics
import DataCompression
import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// Guild emblems: the upload format rAthena validates (`clif_validate_emblem`), reading one back, and when the session
/// asks the server for an emblem.
@MainActor
struct GuildEmblemTests {
    private static let characterID: UInt32 = 150000
    private static let accountID: UInt32 = 2000001
    private static let guildID: UInt32 = 7

    // MARK: - Fixtures

    /// 48 by 48: the left half red, the top right quarter green, the bottom right quarter transparent.
    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 48,
            height: 48,
            bitsPerComponent: 8,
            bytesPerRow: 48 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 48))
        // Core Graphics counts rows from the bottom.
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 24, y: 24, width: 24, height: 24))
        return try #require(context.makeImage())
    }

    /// The pixel of a BMP made by the codec as blue, green, red. Row 0 is the bottom row.
    private func bmpPixel(_ bmp: [UInt8], row: Int, column: Int) -> [UInt8] {
        let offset = 54 + (row * GuildEmblemCodec.side + column) * 3
        return Array(bmp[offset..<offset + 3])
    }

    /// The pixel of an image as red, green, blue, alpha. Row 0 is the top row.
    private func pixel(of image: CGImage, row: Int, column: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (row * image.width + column) * 4
        return Array(pixels[offset..<offset + 4])
    }

    private func le32(_ bytes: [UInt8], at offset: Int) -> Int {
        (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
    }

    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = Self.accountID
        var character = CharacterInfo()
        character.charID = Self.characterID
        character.name = "Leon"

        let context = GameContext.testing
        return PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )
    }

    private func enterGuild(_ session: PlaySession, isMaster: Bool, emblemVersion: Int32) {
        var packet = PACKET_ZC_UPDATE_GDID()
        packet.guildId = Self.guildID
        packet.emblemVersion = emblemVersion
        packet.mode = isMaster ? 0x11 : 0
        packet.isMaster = isMaster ? 1 : 0
        packet.guildName = "Poring Hunters"
        _ = session.handleGuildPacket(packet)
    }

    /// `0152 <packet len>.W <guild id>.L <emblem id>.L <emblem data>.?B`, decoded the way the map client does.
    private func emblemPacket(guildID: UInt32, version: UInt32, data: [UInt8]) throws -> any DecodablePacket {
        func le(_ value: UInt32, bytes: Int) -> [UInt8] {
            (0..<bytes).map { UInt8((value >> (8 * UInt32($0))) & 0xff) }
        }
        let bytes = le(0x152, bytes: 2) + le(UInt32(12 + data.count), bytes: 2) + le(guildID, bytes: 4) + le(version, bytes: 4) + data

        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(bytes)) { packets.append($0) }
        return try #require(packets.first)
    }

    // MARK: - Encode

    @Test func uploadIsAZlibStreamOfABitmapTheServerAccepts() throws {
        let upload = try #require(GuildEmblemCodec.encode(try makeImage()))

        // clif_validate_emblem: inflates into 1800 bytes, wants "BM", bfSize equal to the length, bfOffBits inside.
        let bmp = try Zlib.inflate(upload, capacity: 1800).data
        #expect(bmp.count == 1782)
        #expect(Array(bmp[0..<2]) == [0x42, 0x4d])
        #expect(le32(bmp, at: 2) == bmp.count)
        #expect(le32(bmp, at: 10) == 54)
        // 24 by 24, 24 bits per pixel.
        #expect(le32(bmp, at: 18) == 24)
        #expect(le32(bmp, at: 22) == 24)
        #expect(bmp[28] == 24)
    }

    @Test func bitmapRowsRunBottomUpAndTransparentPixelsAreMagenta() throws {
        let bmp = try #require(GuildEmblemCodec.bmp(from: try makeImage()))

        // Bottom row: red on the left, the transparent quarter on the right.
        #expect(bmpPixel(bmp, row: 0, column: 2) == [0x00, 0x00, 0xff])
        #expect(bmpPixel(bmp, row: 0, column: 21) == [0xff, 0x00, 0xff])
        // Top row: red on the left, green on the right.
        #expect(bmpPixel(bmp, row: 23, column: 2) == [0x00, 0x00, 0xff])
        #expect(bmpPixel(bmp, row: 23, column: 21) == [0x00, 0xff, 0x00])
    }

    // MARK: - Decode

    @Test func uploadedEmblemReadsBackWithTransparency() throws {
        let upload = try #require(GuildEmblemCodec.encode(try makeImage()))

        let image = try #require(GuildEmblemCodec.decode(upload))

        #expect(image.width == 24)
        #expect(image.height == 24)
        #expect(try pixel(of: image, row: 2, column: 2) == [0xff, 0x00, 0x00, 0xff])
        #expect(try pixel(of: image, row: 2, column: 21) == [0x00, 0xff, 0x00, 0xff])
        #expect(try pixel(of: image, row: 21, column: 21)[3] == 0)
    }

    @Test func plainBitmapReadsWithoutInflating() throws {
        let bmp = try #require(GuildEmblemCodec.bmp(from: try makeImage()))

        #expect(GuildEmblemCodec.imageBytes(from: bmp) == bmp)
        #expect(GuildEmblemCodec.decode(bmp) != nil)
    }

    @Test func unreadableDataIsNotAnEmblem() {
        #expect(GuildEmblemCodec.decode([]) == nil)
        #expect(GuildEmblemCodec.decode([0x01, 0x02, 0x03, 0x04]) == nil)
    }

    // MARK: - Session

    @Test func emblemVersionIsAskedForOnce() {
        let session = makeSession()

        enterGuild(session, isMaster: false, emblemVersion: 3)
        #expect(session.guildState.requestedEmblems[Self.guildID] == 3)

        // The same version again changes nothing; a new one is asked for.
        session.requestGuildEmblemIfNeeded(guildID: Self.guildID, version: 3)
        #expect(session.guildState.requestedEmblems[Self.guildID] == 3)
        session.requestGuildEmblemIfNeeded(guildID: Self.guildID, version: 4)
        #expect(session.guildState.requestedEmblems[Self.guildID] == 4)
    }

    @Test func guildWithoutEmblemIsNotAskedFor() {
        let session = makeSession()

        enterGuild(session, isMaster: false, emblemVersion: 0)

        #expect(session.guildState.requestedEmblems[Self.guildID] == nil)
    }

    @Test func guildOfUnknownVersionIsAskedForOnce() {
        let session = makeSession()

        session.requestGuildEmblemIfNeeded(guildID: 9, version: nil)
        #expect(session.guildState.requestedEmblems[9] == 0)

        session.requestGuildEmblemIfNeeded(guildID: 0, version: nil)
        #expect(session.guildState.requestedEmblems[0] == nil)
    }

    @Test func emblemPacketFillsTheCache() throws {
        let session = makeSession()
        enterGuild(session, isMaster: false, emblemVersion: 3)
        let upload = try #require(GuildEmblemCodec.encode(try makeImage()))

        let handled = session.handleGuildPacket(try emblemPacket(guildID: Self.guildID, version: 3, data: upload))

        #expect(handled)
        let emblem = try #require(session.guildState.emblems[Self.guildID])
        #expect(emblem.version == 3)
        #expect(emblem.image.width == 24)

        // The cached version is not asked for again.
        session.guildState.requestedEmblems[Self.guildID] = nil
        session.requestGuildEmblemIfNeeded(guildID: Self.guildID, version: 3)
        #expect(session.guildState.requestedEmblems[Self.guildID] == nil)
    }

    @Test func unreadableEmblemPacketLeavesTheCacheAlone() throws {
        let session = makeSession()
        enterGuild(session, isMaster: false, emblemVersion: 3)

        _ = session.handleGuildPacket(try emblemPacket(guildID: Self.guildID, version: 3, data: [1, 2, 3, 4]))

        #expect(session.guildState.emblems[Self.guildID] == nil)
    }

    @Test func onlyTheMasterChangesTheEmblem() throws {
        let session = makeSession()
        enterGuild(session, isMaster: false, emblemVersion: 0)
        let messageCount = session.messageCenter.messages.count

        session.changeGuildEmblem(fromImageData: Data([1, 2, 3]))

        #expect(session.messageCenter.messages.count == messageCount + 1)
        #expect(session.messageCenter.messages.last?.content == "Only the guild master can change the emblem.")
    }

    @Test func masterIsToldWhenTheFileIsNotAnImage() throws {
        let session = makeSession()
        enterGuild(session, isMaster: true, emblemVersion: 0)

        session.changeGuildEmblem(fromImageData: Data([1, 2, 3]))

        #expect(session.messageCenter.messages.last?.content == "That file is not an image the emblem can be made from.")
    }
}
