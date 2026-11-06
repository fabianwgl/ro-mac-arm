//
//  PacketVersionSupportTests.swift
//  RagnarokPacketsTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import XCTest
@testable import RagnarokPackets

final class PacketVersionSupportTests: XCTestCase {
    func testNilRequestUsesDefaultVersion() throws {
        XCTAssertEqual(try PacketVersionSupport.resolve(requested: nil), PACKET_VERSION)
    }

    func testEmptyRequestUsesDefaultVersion() throws {
        XCTAssertEqual(try PacketVersionSupport.resolve(requested: ""), PACKET_VERSION)
        XCTAssertEqual(try PacketVersionSupport.resolve(requested: "  "), PACKET_VERSION)
    }

    func testSupportedRequestResolves() throws {
        XCTAssertEqual(try PacketVersionSupport.resolve(requested: "20211103"), 20211103)
        XCTAssertEqual(try PacketVersionSupport.resolve(requested: " 20211103\n"), 20211103)
    }

    func testUnsupportedRequestThrows() {
        XCTAssertThrowsError(try PacketVersionSupport.resolve(requested: "20220406")) { error in
            guard let error = error as? UnsupportedPacketVersionError else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(error.requested, "20220406")
            XCTAssertEqual(error.supported, [20211103])
            XCTAssertTrue(error.description.contains("20220406"))
            XCTAssertTrue(error.description.contains("20211103"))
        }
    }

    func testMalformedRequestThrows() {
        for requested in ["abc", "2021110", "202111030", "2021-11-03"] {
            XCTAssertThrowsError(try PacketVersionSupport.resolve(requested: requested)) { error in
                guard let error = error as? UnsupportedPacketVersionError else {
                    return XCTFail("Unexpected error: \(error)")
                }

                XCTAssertEqual(error.requested, requested)
                XCTAssertEqual(error.supported, [20211103])
            }
        }
    }

    func testEnvironmentWithoutKeyUsesDefaultVersion() throws {
        XCTAssertEqual(try PacketVersionSupport.resolveFromEnvironment([:]), PACKET_VERSION)
    }

    func testEnvironmentWithUnsupportedVersionThrows() {
        XCTAssertThrowsError(try PacketVersionSupport.resolveFromEnvironment(["RO_PACKET_VERSION": "20200101"]))
    }

    func testSupportedVersionsContainsDefaultVersion() {
        XCTAssertTrue(PacketVersionSupport.supportedVersions.contains(PACKET_VERSION))
    }
}
