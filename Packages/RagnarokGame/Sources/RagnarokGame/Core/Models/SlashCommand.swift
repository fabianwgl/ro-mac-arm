//
//  SlashCommand.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/10/27.
//

enum SlashCommand: String {
    case `where`
    case sit
    case stand
    case exchange
    case help

    static let helpMessageIDs = [33, 38, 132, 133]

    init?(message: String) {
        guard message.hasPrefix("/"), let name = message.dropFirst().split(separator: " ", maxSplits: 1).first else {
            return nil
        }

        switch name {
        case "h":
            self = .help
        case "ex":
            self = .exchange
        default:
            self.init(rawValue: String(name))
        }
    }
}

extension MessageCenter {
    func addUnknownSlashCommandMessage() {
        let messageString = messageStringTable.localizedMessageString(forID: 95)
        let message = MessageCenter.Message(content: messageString, type: .info, category: .general)
        messages.append(message)
    }

    func addWhisperUsageMessage() {
        let message = MessageCenter.Message(content: "Usage: /w \"Name\" message", type: .info, category: .general)
        messages.append(message)
    }

    func addLocationMessage(mapName: String, localizedMapName: String, position: SIMD2<Int>) {
        let message = MessageCenter.Message(content: "\(localizedMapName)(\(mapName)) : \(position.x), \(position.y)", type: .info, category: .general)
        messages.append(message)
    }

    func addSlashCommandHelpMessages() {
        for messageID in SlashCommand.helpMessageIDs {
            let messageString = messageStringTable.localizedMessageString(forID: messageID)
            let message = MessageCenter.Message(content: messageString, type: .info, category: .general)
            messages.append(message)
        }
    }
}
