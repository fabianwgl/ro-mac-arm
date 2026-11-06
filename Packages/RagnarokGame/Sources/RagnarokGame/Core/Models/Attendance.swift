//
//  Attendance.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// Daily check-in state for the running attendance period.
///
/// The server tells the client two things, both about the player and neither about the period:
/// - `ZC_UI_OPEN` for the attendance UI carries `10 * rewardedDays + (rewardedToday ? 1 : 0)`
///   (`pc_attendance_counter`).
/// - `0x0af0` after a successful check-in carries the new rewarded day count (`clif_attendence_response`).
///
/// The period dates and the reward table are not sent. kRO's `System/CheckAttendance.lub` holds a table
/// (2020-08-05 to 2020-09-01, item IDs per day) that does not match rAthena's `attendance.yml`, so the
/// window shows day numbers only. The server mails the reward.
struct Attendance: Equatable, Sendable {
    enum DayState: Equatable, Sendable {
        /// The day was rewarded.
        case rewarded
        /// The day today's check-in counts for.
        case today
        case upcoming
    }

    /// rAthena's login popup only opens below 200 (`pc_scdata_received`), so a period is 20 days.
    static let defaultDayCount = 20

    private(set) var dayCount: Int
    private(set) var rewardedDays: Int
    private(set) var isRewardedToday: Bool

    /// True after the server sent a state, so the window is not offered an invented one.
    private(set) var hasServerState = false

    /// True between sending a check-in and the server answering or sending the state again.
    private(set) var isCheckInPending = false

    /// Set when the server opens the window. The map view shows it and clears the flag.
    var isPresentationRequested = false

    init(dayCount: Int = Attendance.defaultDayCount, rewardedDays: Int = 0, isRewardedToday: Bool = false) {
        self.dayCount = max(dayCount, 1)
        self.rewardedDays = min(max(rewardedDays, 0), self.dayCount)
        self.isRewardedToday = isRewardedToday
    }

    var isComplete: Bool {
        rewardedDays >= dayCount
    }

    /// The day number today's check-in counts for, from 1 to `dayCount`.
    var currentDay: Int {
        if isRewardedToday {
            max(rewardedDays, 1)
        } else {
            min(rewardedDays + 1, dayCount)
        }
    }

    var canCheckIn: Bool {
        hasServerState && !isRewardedToday && !isComplete && !isCheckInPending
    }

    func state(ofDay day: Int) -> DayState {
        if day <= rewardedDays {
            .rewarded
        } else if day == rewardedDays + 1 && !isRewardedToday && !isComplete {
            .today
        } else {
            .upcoming
        }
    }

    /// Applies the `data` of a `ZC_UI_OPEN` for the attendance UI and asks for the window to be shown.
    mutating func apply(uiOpenData data: Int64) {
        let data = max(data, 0)
        rewardedDays = Int(min(data / 10, Int64(dayCount)))
        isRewardedToday = data % 10 == 1
        hasServerState = true
        isCheckInPending = false
        isPresentationRequested = true
    }

    /// Applies the answer to a check-in: the server rewarded the day and sent the new count.
    mutating func applyCheckIn(rewardedDays: Int) {
        self.rewardedDays = min(max(rewardedDays, 0), dayCount)
        isRewardedToday = true
        hasServerState = true
        isCheckInPending = false
    }

    mutating func beginCheckIn() {
        isCheckInPending = true
    }
}
