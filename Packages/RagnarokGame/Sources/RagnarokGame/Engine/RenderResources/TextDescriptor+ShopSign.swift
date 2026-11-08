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
    /// The title of a player's shop, drawn over his head. A buying store is blue, a shop gold.
    init(shopTitle: String, isBuying: Bool = false) {
        let color: SIMD3<Float> = isBuying ? [0.62, 0.84, 1] : [1, 0.92, 0.55]

        var text = AttributedString(shopTitle)
        #if canImport(UIKit)
        text.uiKit.foregroundColor = UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
        #elseif canImport(AppKit)
        text.appKit.foregroundColor = NSColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
        #endif

        self.init(text: text)
    }
}
