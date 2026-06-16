//
//  VoxtApp.swift
//  Voxt
//
//  Created by morishin on 2026/06/08.
//

import SwiftUI

@main
struct VoxtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバー・アイコン・設定ウィンドウはすべて AppDelegate の
        // StatusItemController / SettingsWindowController(AppKit)が管理する。
        // SwiftUI App は最低 1 つの Scene を要求するため、空の Settings を置くだけ。
        Settings {
            EmptyView()
        }
    }
}
