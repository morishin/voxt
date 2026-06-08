//
//  AppDelegate.swift
//  vkey
//
//  Dock アイコンを出さずメニューバー常駐エージェントとして動作させる。
//

import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // .accessory: Dock に出ず、メニューバーのみで常駐する。
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("vkey launched (accessory mode)")
    }
}
