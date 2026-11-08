//
//  TextDescriptor+ShopSign.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The kinds of title a player shows over his head.
enum SignStyle: Sendable {
    case shop
    case buyingStore
    case chatRoom

    var color: SIMD3<Float> {
        switch self {
        case .shop: [1, 0.92, 0.55]
        case .buyingStore: [0.62, 0.84, 1]
        case .chatRoom: [0.7, 1, 0.72]
        }
    }
}

extension TextDescriptor {
    /// The title of a player's shop, buying store or chat room, drawn over his head. A shop is gold, a buying store
    /// blue, a chat room green.
    init(signTitle: String, style: SignStyle) {
        let color = style.color

        var text = AttributedString(signTitle)
        #if canImport(UIKit)
        text.uiKit.foregroundColor = UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
        #elseif canImport(AppKit)
        text.appKit.foregroundColor = NSColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
        #endif

        self.init(text: text)
    }

    init(shopTitle: String, isBuying: Bool = false) {
        self.init(signTitle: shopTitle, style: isBuying ? .buyingStore : .shop)
    }
}
