import Foundation
import RagnarokPackets
import Testing
@testable import RagnarokGame

struct AttendanceTests {
    @Test func uiOpenDataSplitsCounterAndRewardedToday() {
        var attendance = Attendance()

        // rAthena sends 10 * rewardedDays + (rewardedToday ? 1 : 0).
        attendance.apply(uiOpenData: 0)
        #expect(attendance.rewardedDays == 0)
        #expect(attendance.isRewardedToday == false)
        #expect(attendance.currentDay == 1)

        attendance.apply(uiOpenData: 70)
        #expect(attendance.rewardedDays == 7)
        #expect(attendance.isRewardedToday == false)
        #expect(attendance.currentDay == 8)

        attendance.apply(uiOpenData: 71)
        #expect(attendance.rewardedDays == 7)
        #expect(attendance.isRewardedToday == true)
        #expect(attendance.currentDay == 7)
    }

    @Test func uiOpenRequestsPresentationAndEnablesCheckIn() {
        var attendance = Attendance()
        #expect(attendance.canCheckIn == false)
        #expect(attendance.isPresentationRequested == false)

        attendance.apply(uiOpenData: 30)

        #expect(attendance.hasServerState)
        #expect(attendance.isPresentationRequested)
        #expect(attendance.canCheckIn)
    }

    @Test func cannotCheckInTwiceOrAfterRewardedToday() {
        var attendance = Attendance()
        attendance.apply(uiOpenData: 30)

        attendance.beginCheckIn()
        #expect(attendance.canCheckIn == false)

        attendance.applyCheckIn(rewardedDays: 4)
        #expect(attendance.rewardedDays == 4)
        #expect(attendance.isRewardedToday)
        #expect(attendance.isCheckInPending == false)
        #expect(attendance.canCheckIn == false)
        #expect(attendance.currentDay == 4)

        attendance.apply(uiOpenData: 41)
        #expect(attendance.canCheckIn == false)
    }

    @Test func reopeningAfterNoAnswerAllowsCheckInAgain() {
        var attendance = Attendance()
        attendance.apply(uiOpenData: 30)
        attendance.beginCheckIn()

        attendance.apply(uiOpenData: 30)

        #expect(attendance.canCheckIn)
    }

    @Test func dayStates() {
        var attendance = Attendance()
        attendance.apply(uiOpenData: 30)

        #expect(attendance.state(ofDay: 1) == .rewarded)
        #expect(attendance.state(ofDay: 3) == .rewarded)
        #expect(attendance.state(ofDay: 4) == .today)
        #expect(attendance.state(ofDay: 5) == .upcoming)
        #expect(attendance.state(ofDay: 20) == .upcoming)

        attendance.applyCheckIn(rewardedDays: 4)

        #expect(attendance.state(ofDay: 4) == .rewarded)
        #expect(attendance.state(ofDay: 5) == .upcoming)
        #expect((1...20).filter { attendance.state(ofDay: $0) == .today }.isEmpty)
    }

    @Test func completedPeriodHasNoDayToCheckIn() {
        var attendance = Attendance()

        attendance.apply(uiOpenData: 200)

        #expect(attendance.isComplete)
        #expect(attendance.rewardedDays == 20)
        #expect(attendance.canCheckIn == false)
        #expect(attendance.currentDay == 20)
        #expect((1...20).allSatisfy { attendance.state(ofDay: $0) == .rewarded })
    }

    @Test func outOfRangeDataIsClamped() {
        var attendance = Attendance()

        attendance.apply(uiOpenData: 9_999)
        #expect(attendance.rewardedDays == 20)

        attendance.apply(uiOpenData: -5)
        #expect(attendance.rewardedDays == 0)
        #expect(attendance.isRewardedToday == false)

        attendance.applyCheckIn(rewardedDays: 500)
        #expect(attendance.rewardedDays == 20)
    }

    @MainActor
    @Test func uiOpenPacketOpensAttendanceAndIgnoresOtherTypes() {
        let playSession = PlaySession(context: .testing)

        // Unknown and unsupported UI types change nothing and are handled.
        for uiType: Int8 in [0, 1, 2, 3, 5, 6, 8, 10, 99] {
            var packet = PACKET_ZC_UI_OPEN()
            packet.packetType = HEADER_ZC_UI_OPEN
            packet.UIType = uiType
            packet.data = 71
            #expect(playSession.handleAttendancePacket(packet))
            #expect(playSession.attendance == Attendance())
        }

        var packet = PACKET_ZC_UI_OPEN()
        packet.packetType = HEADER_ZC_UI_OPEN
        packet.UIType = 7
        packet.data = 51
        #expect(playSession.handleAttendancePacket(packet))
        #expect(playSession.attendance.rewardedDays == 5)
        #expect(playSession.attendance.isRewardedToday)
        #expect(playSession.attendance.isPresentationRequested)
    }

    @MainActor
    @Test func v3UIOpenPacketIsHandledTheSameWay() {
        let playSession = PlaySession(context: .testing)

        var enchant = PACKET_ZC_UI_OPEN_V3()
        enchant.packetType = HEADER_ZC_UI_OPEN_V3
        enchant.type = 10
        enchant.data = 1234
        #expect(playSession.handleAttendancePacket(enchant))
        #expect(playSession.attendance == Attendance())

        var attendance = PACKET_ZC_UI_OPEN_V3()
        attendance.packetType = HEADER_ZC_UI_OPEN_V3
        attendance.type = 7
        attendance.data = 20
        #expect(playSession.handleAttendancePacket(attendance))
        #expect(playSession.attendance.rewardedDays == 2)
        #expect(playSession.attendance.isRewardedToday == false)
    }

    @MainActor
    @Test func checkInAckMarksTodayRewardedAndAddsMessage() throws {
        let playSession = PlaySession(context: .testing)
        playSession.attendance.apply(uiOpenData: 30)

        // 0x0af0 <unknown>.L <data>.L, as clif_attendence_response writes it.
        let bytes: [UInt8] = [0xf0, 0x0a, 0, 0, 0, 0, 4, 0, 0, 0]
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(bytes)) { packets.append($0) }

        #expect(packets.count == 1)
        let messageCount = playSession.messageCenter.messages.count
        #expect(playSession.handleAttendancePacket(try #require(packets.first)))
        #expect(playSession.attendance.rewardedDays == 4)
        #expect(playSession.attendance.isRewardedToday)
        #expect(playSession.messageCenter.messages.count == messageCount + 1)
    }

    @MainActor
    @Test func otherPacketsAreNotHandled() {
        let playSession = PlaySession(context: .testing)

        #expect(playSession.handleAttendancePacket(makeNotifyTimePacket()) == false)
    }
}

private func makeNotifyTimePacket() -> PACKET_ZC_NOTIFY_TIME {
    var packet = PACKET_ZC_NOTIFY_TIME()
    packet.packetType = HEADER_ZC_NOTIFY_TIME
    return packet
}
