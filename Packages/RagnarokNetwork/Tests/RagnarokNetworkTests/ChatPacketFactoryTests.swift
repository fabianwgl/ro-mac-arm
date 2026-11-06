//
//  ChatPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Chat packet factory")
struct ChatPacketFactoryTests {
    @Test func whisperPacket() throws {
        let receiver = "Some Name"
        let message = "hello"
        let packet = PacketFactory.CZ_WHISPER(receiver: receiver, message: message)

        #expect(packet.packetType == HEADER_CZ_WHISPER)

        let data = try PacketEncoder().encode(packet)
        #expect(Int(packet.packetLength) == data.count)

        let bytes = [UInt8](data)
        #expect(Array(bytes[4..<(4 + receiver.utf8.count)]) == [UInt8](receiver.utf8))
        #expect(Array(bytes[28..<(28 + message.utf8.count)]) == [UInt8](message.utf8))
    }

    @Test func partyChatPacket() throws {
        let message = "Leon : hello"
        let packet = PacketFactory.CZ_REQUEST_CHAT_PARTY(message: message)

        #expect(packet.packetType == HEADER_CZ_REQUEST_CHAT_PARTY)

        let data = try PacketEncoder().encode(packet)
        #expect(Int(packet.packetLength) == data.count)

        let bytes = [UInt8](data)
        #expect(Array(bytes[4..<(4 + message.utf8.count)]) == [UInt8](message.utf8))
    }

    @Test func guildChatPacket() throws {
        let message = "Leon : hello"
        let packet = PacketFactory.CZ_GUILD_CHAT(message: message)

        #expect(packet.packetType == HEADER_CZ_GUILD_CHAT)

        let data = try PacketEncoder().encode(packet)
        #expect(Int(packet.packetLength) == data.count)

        let bytes = [UInt8](data)
        #expect(Array(bytes[4..<(4 + message.utf8.count)]) == [UInt8](message.utf8))
    }
}

@Suite("Chat command parser")
struct ChatCommandParserTests {
    @Test func quotedWhisperName() {
        let result = ChatCommandParser.whisperCommand(from: "/w \"Some Name\" hello")
        #expect(result == .whisper(receiver: "Some Name", message: "hello"))
    }

    @Test func unquotedWhisperName() {
        let result = ChatCommandParser.whisperCommand(from: "/w Name hello")
        #expect(result == .whisper(receiver: "Name", message: "hello"))
    }

    @Test func longWhisperCommand() {
        let result = ChatCommandParser.whisperCommand(from: "/whisper Name hello")
        #expect(result == .whisper(receiver: "Name", message: "hello"))
    }

    @Test func missingText() {
        #expect(ChatCommandParser.whisperCommand(from: "/w Name") == .usage)
        #expect(ChatCommandParser.whisperCommand(from: "/w \"Some Name\"") == .usage)
    }

    @Test func missingName() {
        #expect(ChatCommandParser.whisperCommand(from: "/w") == .usage)
        #expect(ChatCommandParser.whisperCommand(from: "/w hello") == .usage)
    }

    @Test func notWhisperCommand() {
        #expect(ChatCommandParser.whisperCommand(from: "/where") == .notWhisper)
        #expect(ChatCommandParser.whisperCommand(from: "%hello") == .notWhisper)
    }
}
