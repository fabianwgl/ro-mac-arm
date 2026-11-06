//
//  ChatCommandParser.swift
//  RagnarokNetwork
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

public enum ChatCommandParser {
    public enum WhisperResult: Equatable, Sendable {
        case notWhisper
        case usage
        case whisper(receiver: String, message: String)
    }

    public static func whisperCommand(from text: String) -> WhisperResult {
        let text = text.trimmingCharacters(in: .whitespaces)
        let lowercasedText = text.lowercased()

        let command: String
        if lowercasedText == "/whisper" || lowercasedText.hasPrefix("/whisper ") {
            command = "/whisper"
        } else if lowercasedText == "/w" || lowercasedText.hasPrefix("/w ") {
            command = "/w"
        } else {
            return .notWhisper
        }

        let arguments = String(text.dropFirst(command.count)).trimmingCharacters(in: .whitespaces)
        guard !arguments.isEmpty else {
            return .usage
        }

        let receiver: String
        let message: String

        if arguments.hasPrefix("\"") {
            let quotedArguments = arguments.dropFirst()
            guard let closingQuote = quotedArguments.firstIndex(of: "\"") else {
                return .usage
            }
            receiver = String(quotedArguments[..<closingQuote])
            message = String(quotedArguments[quotedArguments.index(after: closingQuote)...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            guard let separator = arguments.firstIndex(of: " ") else {
                return .usage
            }
            receiver = String(arguments[..<separator])
            message = String(arguments[arguments.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
        }

        guard !receiver.isEmpty, !message.isEmpty else {
            return .usage
        }

        return .whisper(receiver: receiver, message: message)
    }
}
