//
//  AttendanceView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

struct AttendanceView: View {
    var attendance: Attendance
    var onClose: () -> Void = {}

    @Environment(PlaySession.self) private var playSession

    private let columnCount = 5

    var body: some View {
        GameWindow {
            VStack(alignment: .leading, spacing: 5) {
                summary

                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { day in
                                AttendanceDayCell(day: day, state: attendance.state(ofDay: day))
                            }
                        }
                    }
                }

                Text(verbatim: "Each day's reward is sent to your mail.")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
            }
            .padding(5)
        } bottomBar: {
            GameBottomBar {
                Button {
                    playSession.checkInAttendance()
                } label: {
                    Text(verbatim: "Check in")
                }
                .buttonStyle(.game)
                .frame(width: 72, height: 20)
                .disabled(!attendance.canCheckIn)
            }
        }
        .gameWindowTitle(Text(verbatim: "Attendance"))
        .gameWindowCloseAction(onClose)
        .frame(width: 280)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "Day \(attendance.currentDay) of \(attendance.dayCount)")
                .font(.game())
                .foregroundStyle(Color.gameLabel)

            Text(verbatim: statusText)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9568627451, blue: 0.9411764706, alpha: 1)))
    }

    private var statusText: String {
        if attendance.isComplete {
            "All \(attendance.dayCount) days are checked in."
        } else if attendance.isRewardedToday {
            "Checked in today. Come back tomorrow."
        } else {
            "You have not checked in today."
        }
    }

    private var rows: [[Int]] {
        Array(1...attendance.dayCount).chunked(into: columnCount)
    }
}

private struct AttendanceDayCell: View {
    var day: Int
    var state: Attendance.DayState

    var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: "\(day)")
                .font(.game())
                .foregroundStyle(Color.gameLabel)

            Image(systemName: state == .rewarded ? "checkmark.circle.fill" : "circle")
                .font(.game(size: 12))
                .foregroundStyle(state == .rewarded ? Color.green : Color.gameProminentLabel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .circular)
                .strokeBorder(state == .today ? Color.gameProminentLabel : Color.gameBoxBorder, lineWidth: state == .today ? 2 : 1)
        }
        .opacity(state == .upcoming ? 0.6 : 1)
    }

    private var background: Color {
        switch state {
        case .rewarded:
            Color(#colorLiteral(red: 0.9137254902, green: 0.9764705882, blue: 0.9137254902, alpha: 1))
        case .today:
            Color(#colorLiteral(red: 0.9137254902, green: 0.9411764706, blue: 0.9803921569, alpha: 1))
        case .upcoming:
            Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1))
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

#Preview {
    AttendanceView(attendance: Attendance(rewardedDays: 6))
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
