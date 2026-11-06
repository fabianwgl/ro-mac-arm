//
//  PacketReplayTests.swift
//  RagnarokNetwork
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokPackets
import Testing
@testable import RagnarokNetwork

private func sampleRecording() -> PacketRecording {
    PacketRecording(
        clientName: "Map",
        startTime: Date(timeIntervalSince1970: 1_700_000_000.125),
        records: [
            PacketRecord(milliseconds: 0, kind: .inbound, payload: Data([0x01, 0x02])),
            PacketRecord(milliseconds: 15, kind: .outbound, payload: Data([0x03])),
            PacketRecord(milliseconds: 250, kind: .inboundPrefix, payload: Data([0xaa, 0xbb, 0xcc, 0xdd])),
            PacketRecord(milliseconds: 500, kind: .event, payload: Data("connected".utf8)),
        ]
    )
}

@Test func recordingRoundTrip() throws {
    let recording = sampleRecording()
    let decoded = try PacketRecording(data: recording.encoded())
    #expect(decoded == recording)
}

@Test func recordingRejectsBadMagic() throws {
    var data = sampleRecording().encoded()
    data[data.startIndex] = 0x00

    #expect(throws: PacketRecordingError.badMagic) {
        try PacketRecording(data: data)
    }
}

@Test func recordingRejectsUnsupportedVersion() throws {
    var data = sampleRecording().encoded()
    data[data.startIndex + 4] = 2
    data[data.startIndex + 5] = 0

    #expect(throws: PacketRecordingError.unsupportedVersion(2)) {
        try PacketRecording(data: data)
    }
}

@Test func recordingRejectsTruncatedData() throws {
    let data = Data(sampleRecording().encoded().dropLast())

    #expect(throws: PacketRecordingError.truncated) {
        try PacketRecording(data: data)
    }
}

@Test func recorderWritesReadableFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let recorder = try PacketRecorder(directory: directory, clientName: "Login", now: now)

    let records = [
        PacketRecord(milliseconds: 0, kind: .inbound, payload: Data([0x01, 0x02])),
        PacketRecord(milliseconds: 0, kind: .outbound, payload: Data([0x03])),
        PacketRecord(milliseconds: 0, kind: .inboundPrefix, payload: Data([0x04, 0x05, 0x06, 0x07])),
        PacketRecord(milliseconds: 0, kind: .event, payload: Data("ready".utf8)),
    ]
    for record in records {
        recorder.record(record.kind, record.payload)
    }
    recorder.close()

    let data = try Data(contentsOf: recorder.fileURL)
    let recording = try PacketRecording(data: data)

    #expect(recording.clientName == "Login")
    #expect(recording.startTime == now)
    #expect(recording.records.map(\.kind) == records.map(\.kind))
    #expect(recording.records.map(\.payload) == records.map(\.payload))
}

@Test func replayDecodesInboundPackets() throws {
    var notifyTime = PACKET_ZC_NOTIFY_TIME()
    notifyTime.packetType = HEADER_ZC_NOTIFY_TIME
    notifyTime.time = 123_456

    let message = "hello"
    var notifyChat = PACKET_ZC_NOTIFY_CHAT()
    notifyChat.packetType = HEADER_ZC_NOTIFY_CHAT
    notifyChat.packetLength = Int16(2 + 2 + 4 + message.utf8.count)
    notifyChat.GID = 2_000_000
    notifyChat.Message = message

    let encoder = PacketEncoder()
    let timeData = try encoder.encode(notifyTime)
    let chatData = try encoder.encode(notifyChat)
    let allData = timeData + chatData

    let recording = PacketRecording(
        clientName: "Map",
        startTime: Date(timeIntervalSince1970: 1_700_000_000),
        records: [
            PacketRecord(milliseconds: 0, kind: .inbound, payload: Data(allData.prefix(3))),
            PacketRecord(milliseconds: 1, kind: .inbound, payload: Data(allData.dropFirst(3).prefix(4))),
            PacketRecord(milliseconds: 2, kind: .inbound, payload: Data(allData.dropFirst(7))),
            PacketRecord(milliseconds: 3, kind: .outbound, payload: Data([0x01])),
            PacketRecord(milliseconds: 4, kind: .inboundPrefix, payload: Data(repeating: 0, count: 4)),
        ]
    )

    let result = PacketReplay.replay(recording)

    #expect(result.packets.count == 2)
    #expect(result.errors.isEmpty)
    #expect(result.outboundCount == 1)

    let decodedTime = result.packets[0] as? PACKET_ZC_NOTIFY_TIME
    #expect(decodedTime?.packetType == HEADER_ZC_NOTIFY_TIME)
    #expect(decodedTime?.time == 123_456)

    let decodedChat = result.packets[1] as? PACKET_ZC_NOTIFY_CHAT
    #expect(decodedChat?.GID == 2_000_000)
    #expect(decodedChat?.Message == message)
}

@Test func replayCollectsErrorsAndContinues() throws {
    var notifyTime = PACKET_ZC_NOTIFY_TIME()
    notifyTime.packetType = HEADER_ZC_NOTIFY_TIME
    notifyTime.time = 42

    let timeData = try PacketEncoder().encode(notifyTime)

    let recording = PacketRecording(
        clientName: "Map",
        startTime: Date(timeIntervalSince1970: 1_700_000_000),
        records: [
            PacketRecord(milliseconds: 0, kind: .inbound, payload: Data([0xff, 0x7f])),
            PacketRecord(milliseconds: 1, kind: .inbound, payload: timeData),
        ]
    )

    let result = PacketReplay.replay(recording)

    #expect(result.errors.count == 1)
    #expect(result.packets.count == 1)

    let decodedTime = result.packets.first as? PACKET_ZC_NOTIFY_TIME
    #expect(decodedTime?.time == 42)
}

@Test func recorderFromEmptyEnvironmentReturnsNil() {
    #expect(PacketRecorder.fromEnvironment(clientName: "Map", environment: [:]) == nil)
    #expect(PacketRecorder.fromEnvironment(
        clientName: "Map",
        environment: [PacketRecorder.environmentKey: ""]
    ) == nil)
}
