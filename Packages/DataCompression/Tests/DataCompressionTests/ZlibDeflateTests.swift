//
//  ZlibDeflateTests.swift
//  DataCompressionTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Testing
@testable import DataCompression

@Test func deflateWritesAZlibStreamInflateReads() throws {
    let bytes = (0..<4000).map { UInt8(($0 / 7) & 0xff) }

    let stream = try #require(Zlib.deflate(bytes))

    // RFC 1950: the deflate method with a 32 KB window, and a header that is a multiple of 31.
    #expect(stream[0] == 0x78)
    #expect((Int(stream[0]) << 8 | Int(stream[1])) % 31 == 0)
    #expect(stream.count < bytes.count)

    let result = try Zlib.inflate(stream)
    #expect(result.data == bytes)
    #expect(result.consumed == stream.count)
}

@Test func deflateOfNothingRoundTrips() throws {
    let stream = try #require(Zlib.deflate([]))

    #expect(try Zlib.inflate(stream).data.isEmpty)
}
