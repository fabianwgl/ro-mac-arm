//
//  ForkNotice.swift
//  RO Mac Client
//
//  Created by RO Mac Client contributors on 2026/11/5.
//

// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Location of the RO Mac Client source code, offered to every user as required by the GPL.
/// Placeholder until the fork repository is published.
let forkRepositoryURL = "https://github.com/fabianwgl/ro-mac-arm"

/// Fork attribution and licensing statement shown in the About screen.
struct ForkNoticeSection: View {
    var body: some View {
        Section {
            Text("""
            RO Mac Client is a fork of Ragnarok Offline by Leon Li (github.com/arkadeleon/ragnarok-offline), \
            licensed under GPL-3.0. Source code: \(forkRepositoryURL). \
            Packet definitions derived from rAthena (GPL-3.0). \
            Ragnarok Online assets are not included; you must supply your own kRO client files.
            """, tableName: "Settings")
                .textSelection(.enabled)
        } header: {
            Text("Fork Notice", tableName: "Settings")
        }
    }
}

#Preview {
    Form {
        ForkNoticeSection()
    }
    .formStyle(.grouped)
}
