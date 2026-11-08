//
//  Bundle+Locale.swift
//  RagnarokLocalization
//
//  Created by Leon Li on 2024/5/27.
//

import Foundation

extension Bundle {
    /// The localization of this bundle that `locale` maps to, for example `en` for `en_PT` and `pt-BR` for `pt_PT`.
    func localization(for locale: Locale) -> String {
        Bundle.preferredLocalizations(from: localizations, forPreferences: [locale.identifier])[0]
    }

    func url(forResource name: String?, withExtension ext: String?, locale: Locale) -> URL? {
        url(forResource: name, withExtension: ext, subdirectory: nil, localization: localization(for: locale))
    }
}
