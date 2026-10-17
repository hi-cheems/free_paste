//
//  FreePasteApp.swift
//  FreePaste
//
//  Created by bond cheems on 2026/3/12.
//

import SwiftUI

@main
struct FreePasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // UI is managed by AppDelegate via NSStatusItem + NSPanel.
        Settings { EmptyView() }
    }
}
