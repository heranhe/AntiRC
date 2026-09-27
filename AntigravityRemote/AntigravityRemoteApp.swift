//
//  AntigravityRemoteApp.swift
//  AntigravityRemote
//
//  应用程序入口与主生命周期
//

import SwiftUI

@main
struct AntigravityRemoteApp: App {
    @StateObject private var settings = AppSettings.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--native-conversation-preview") {
                    nativeConversationPreview()
                } else {
                    MainContainerView(settings: settings)
                }
#else
                MainContainerView(settings: settings)
#endif
            }
                .onAppear {
                    settings.updateIdleTimer()
                }
        }
    }
}
