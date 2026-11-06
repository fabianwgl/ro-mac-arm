import RagnarokConstants
import RagnarokModels
import Testing
@testable import RagnarokGame

@Test func directionFromPositionToPosition() {
    let origin = SIMD2(10, 10)

    #expect(Direction(fromPosition: origin, toPosition: SIMD2(10, 11)) == .north)
    #expect(Direction(fromPosition: origin, toPosition: SIMD2(11, 11)) == .northeast)
    #expect(Direction(fromPosition: origin, toPosition: SIMD2(11, 10)) == .east)
    #expect(Direction(fromPosition: origin, toPosition: SIMD2(11, 9)) == .southeast)
    #expect(Direction(fromPosition: origin, toPosition: SIMD2(10, 9)) == .south)
    #expect(Direction(fromPosition: origin, toPosition: SIMD2(9, 9)) == .southwest)
    #expect(Direction(fromPosition: origin, toPosition: SIMD2(9, 10)) == .west)
    #expect(Direction(fromPosition: origin, toPosition: SIMD2(9, 11)) == .northwest)
    #expect(Direction(fromPosition: origin, toPosition: origin) == .south)
}

@Test func mapServerInfoConvertsNetworkAddress() {
    let mapServer = MapServerInfo(ip: 0x0100_007F, port: 5121)

    #expect(mapServer.ip == "127.0.0.1")
    #expect(mapServer.port == 5121)
}
