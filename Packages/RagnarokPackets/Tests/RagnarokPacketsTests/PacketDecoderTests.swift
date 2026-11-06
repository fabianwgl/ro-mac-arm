//
//  PacketDecoderTests.swift
//  RagnarokPacketsTests
//
//  Created by Leon Li on 2025/11/5.
//

import Foundation
import XCTest
@testable import RagnarokPackets

final class PacketDecoderTests: XCTestCase {
    func testCoalescedPackets() throws {
        let data = try makeTestPackets()

        let decoder = PacketDecoder()
        var packets: [any DecodablePacket] = []
        try decoder.decode(from: data) { packet in
            packets.append(packet)
        }

        assertTestPackets(packets)
    }

    func testFragmentedPackets() throws {
        let data = try makeTestPackets()

        let decoder = PacketDecoder()
        var packets: [any DecodablePacket] = []
        for byte in data {
            try decoder.decode(from: Data([byte])) { packet in
                packets.append(packet)
            }
        }

        assertTestPackets(packets)
    }

    func testEverySplitPoint() throws {
        let data = try makeTestPackets()

        for splitIndex in 0...data.count {
            let decoder = PacketDecoder()
            var packets: [any DecodablePacket] = []

            try decoder.decode(from: data.prefix(splitIndex)) { packet in
                packets.append(packet)
            }
            try decoder.decode(from: data.dropFirst(splitIndex)) { packet in
                packets.append(packet)
            }

            assertTestPackets(packets, message: "split at \(splitIndex)")
        }
    }

    func testUnknownPacket() throws {
        let unknownPacketType = findUnknownPacketType()
        var unknownData = encodedPacketType(unknownPacketType)
        unknownData.append(contentsOf: [0x01, 0x02, 0x03, 0x04])

        let decoder = PacketDecoder()
        var packets: [any DecodablePacket] = []

        XCTAssertThrowsError(try decoder.decode(from: unknownData) { packet in
            packets.append(packet)
        }) { error in
            guard case PacketDecodingError.unknownPacket(let packetType) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(packetType, unknownPacketType)
        }
        XCTAssertEqual(packets.count, 0)

        let data = try makeTestPackets()
        try decoder.decode(from: data) { packet in
            packets.append(packet)
        }

        assertTestPackets(packets)
    }

    func testInvalidPacketLength() throws {
        var packet = PACKET_ZC_NOTIFY_CHAT()
        packet.packetType = HEADER_ZC_NOTIFY_CHAT
        packet.packetLength = 3

        let data = try PacketEncoder().encode(packet)

        let decoder = PacketDecoder()
        XCTAssertThrowsError(try decoder.decode(from: data) { _ in }) { error in
            guard case PacketDecodingError.invalidPacketLength(let packetType, let packetLength) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(packetType, HEADER_ZC_NOTIFY_CHAT)
            XCTAssertEqual(packetLength, 3)
        }
    }

    func testBufferOverflow() throws {
        let data = Data(repeating: 0, count: PacketDecoder.maximumBufferedBytes + 1)

        let decoder = PacketDecoder()
        XCTAssertThrowsError(try decoder.decode(from: data) { _ in }) { error in
            guard case PacketDecodingError.bufferOverflow(let bufferedByteCount) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(bufferedByteCount, PacketDecoder.maximumBufferedBytes + 1)
        }
    }

    func testPacketHexDump() {
        XCTAssertEqual(packetHexDump(Data()), "")
        XCTAssertEqual(packetHexDump(Data([0x7f, 0x00, 0x01])), "7f 00 01")
        XCTAssertEqual(packetHexDump(Data([0xff, 0x01, 0x02, 0x03]), limit: 2), "ff 01 ... (+2 bytes)")
        XCTAssertEqual(packetHexDump(Data([0x00, 0x11, 0x22, 0x33]).dropFirst(2)), "22 33")
    }

    private func makeTestPackets() throws -> Data {
        var timePacket = PACKET_ZC_NOTIFY_TIME()
        timePacket.packetType = HEADER_ZC_NOTIFY_TIME
        timePacket.time = 0x12345678

        var chatPacket = PACKET_ZC_NOTIFY_CHAT()
        chatPacket.packetType = HEADER_ZC_NOTIFY_CHAT
        chatPacket.GID = 0x11223344
        chatPacket.Message = "hello"
        chatPacket.packetLength = Int16(2 + 2 + 4 + chatPacket.Message.utf8.count)

        let encoder = PacketEncoder()
        var data = try encoder.encode(timePacket)
        data.append(try encoder.encode(chatPacket))
        return data
    }

    private func assertTestPackets(_ packets: [any DecodablePacket], message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(packets.count, 2, message, file: file, line: line)
        guard packets.count == 2 else {
            return
        }

        let timePacket = packets[0] as? PACKET_ZC_NOTIFY_TIME
        XCTAssertEqual(timePacket?.time, UInt32(0x12345678), message, file: file, line: line)

        let chatPacket = packets[1] as? PACKET_ZC_NOTIFY_CHAT
        XCTAssertEqual(chatPacket?.GID, UInt32(0x11223344), message, file: file, line: line)
        XCTAssertEqual(chatPacket?.Message, "hello", message, file: file, line: line)
    }

    private func findUnknownPacketType() -> Int16 {
        var packetType: Int16 = 1
        while registeredPackets[packetType] != nil || packetDatabase.entriesByPacketType[packetType] != nil {
            packetType += 1
        }
        return packetType
    }

    private func encodedPacketType(_ packetType: Int16) -> Data {
        var packetType = packetType
        return withUnsafeBytes(of: &packetType) { Data($0) }
    }
}
