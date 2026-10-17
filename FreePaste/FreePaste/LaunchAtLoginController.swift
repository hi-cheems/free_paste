//
//  LaunchAtLoginController.swift
//  FreePaste
//
//  Created by Codex on 2026/3/16.
//

import Foundation
import ServiceManagement

protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
