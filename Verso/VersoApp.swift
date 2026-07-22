//
//  VersoApp.swift
//  Verso
//
//  Created by Leo Chen on 2026/7/22.
//

import SwiftUI

@main
struct VersoApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
        }
        .defaultSize(width: 1120, height: 720)
    }
}
