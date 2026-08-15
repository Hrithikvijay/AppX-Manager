//
//  AppX_ManagerApp.swift
//  AppX Manager
//
//  Created by Hrithik Kumar V on 15/08/26.
//

import SwiftUI

@main
struct AppX_ManagerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(
            width: Theme.Layout.defaultWindowSize.width,
            height: Theme.Layout.defaultWindowSize.height
        )
    }
}
