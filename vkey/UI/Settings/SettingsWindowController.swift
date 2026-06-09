//
//  SettingsWindowController.swift
//  vkey
//
//  設定画面を自前の NSWindow で管理する。
//  macOS では AppKit から SwiftUI の Settings シーンを開けない（showSettingsWindow: が
//  塞がれ「Please use SettingsLink」になる）ため、SettingsView を NSHostingController で
//  ホストした独自ウィンドウを使う。
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {

    private let settings: SettingsStore
    private let permissions: PermissionManager
    private let languages: LanguageManager
    private let navigation: SettingsNavigation
    private var window: NSWindow?

    init(settings: SettingsStore,
         permissions: PermissionManager,
         languages: LanguageManager,
         navigation: SettingsNavigation) {
        self.settings = settings
        self.permissions = permissions
        self.languages = languages
        self.navigation = navigation
    }

    /// 設定ウィンドウを前面に表示する。tab を指定するとそのタブを選択する。
    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.selectedTab = tab }

        if window == nil {
            let root = SettingsView()
                .environmentObject(settings)
                .environmentObject(permissions)
                .environmentObject(languages)
                .environmentObject(navigation)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "vkey 設定"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // 別 Space で開いても現在の Space に出すようにする。
            window.collectionBehavior = [.moveToActiveSpace]
            window.center()
            self.window = window
        }

        // accessory アプリでは activate だけだと他アプリの裏に回ることがあるため、
        // orderFrontRegardless で確実に最前面へ出す。
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
