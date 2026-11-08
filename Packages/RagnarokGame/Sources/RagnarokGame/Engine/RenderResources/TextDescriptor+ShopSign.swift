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

extension TextDescriptor {
    /// The title of a player's shop, drawn over his head.
    init(shopTitle: String) {
        var text = AttributedString(shopTitle)
        #if canImport(UIKit)
        text.uiKit.foregroundColor = UIColor(red: 1, green: 0.92, blue: 0.55, alpha: 1)
        #elseif canImport(AppKit)
        text.appKit.foregroundColor = NSColor(red: 1, green: 0.92, blue: 0.55, alpha: 1)
        #endif

        self.init(text: text)
    }
}
