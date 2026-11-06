//
//  PlaySession+Attendance.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets

/// The UI types the server asks the client to open: `out_ui_type` in rAthena's `clif.hpp`.
enum ServerUIType: Int, Sendable {
    case bank = 0
    case stylist = 1
    case captcha = 2
    case macro = 3
    case tip = 5
    case quest = 6
    case attendance = 7
    case enchantGrade = 8
    case enchant = 10
}

/// The UI type the client sends in `CZ_OPEN_UI` to ask for the attendance window: `IN_UI_ATTENDANCE`.
private let attendanceRequestUIType: Int8 = 5

extension PlaySession {
    /// Handles `ZC_UI_OPEN` and attendance packets. Returns false when the packet is none of them.
    func handleAttendancePacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_UI_OPEN:
            handleUIOpen(type: Int(packet.UIType), data: Int64(packet.data))
        case let packet as PACKET_ZC_UI_OPEN_V3:
            handleUIOpen(type: Int(packet.type), data: Int64(bitPattern: packet.data))
        case let packet as PACKET_ZC_ACK_CHECK_ATTENDANCE:
            attendance.applyCheckIn(rewardedDays: Int(clamping: packet.rewardedDays))
            addAttendanceMessage("Attendance: day \(attendance.currentDay) checked in. The reward was sent to your mail.")
        default:
            return false
        }
        return true
    }

    /// Opens the window for the UI type, or logs and ignores a type the client does not have.
    private func handleUIOpen(type: Int, data: Int64) {
        guard let uiType = ServerUIType(rawValue: type) else {
            logger.info("Ignoring ZC_UI_OPEN of unknown UI type \(type, privacy: .public), data \(data, privacy: .public)")
            return
        }

        switch uiType {
        case .attendance:
            attendance.apply(uiOpenData: data)
        case .bank, .stylist, .captcha, .macro, .tip, .quest, .enchantGrade, .enchant:
            logger.info("Ignoring ZC_UI_OPEN of unsupported UI type \(type, privacy: .public) (\(String(describing: uiType), privacy: .public)), data \(data, privacy: .public)")
        }
    }

    // MARK: - Requests

    /// Asks the server to open the attendance window. It answers with `ZC_UI_OPEN`, or with a message
    /// when attendance is off or no period is running.
    func requestAttendanceWindow() {
        sendPacket(PacketFactory.CZ_OPEN_UI(uiType: attendanceRequestUIType))
    }

    /// Asks the server for today's reward. The server mails it and answers with the new day count.
    func checkInAttendance() {
        guard attendance.canCheckIn else {
            return
        }

        attendance.beginCheckIn()
        sendPacket(PacketFactory.CZ_REQ_CHECK_ATTENDANCE())
    }

    private func addAttendanceMessage(_ content: String) {
        let message = MessageCenter.Message(content: content, type: .system, category: .general)
        messageCenter.messages.append(message)
    }
}
