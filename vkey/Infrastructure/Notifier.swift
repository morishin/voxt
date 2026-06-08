//
//  Notifier.swift
//  vkey
//
//  ユーザー通知（挿入 fallback や処理失敗の通知）。設定で ON のときのみ使う。
//

import Foundation
import UserNotifications
import OSLog

@MainActor
final class Notifier {

    private var authorized = false

    /// 通知の許可を要求する（初回のみダイアログ表示）。
    func requestAuthorization() async {
        do {
            authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            authorized = false
        }
    }

    /// 通知を表示する。
    func notify(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
