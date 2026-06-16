//
//  SettingsNavigation.swift
//  vkey
//
//  設定画面の選択中タブを共有し、メニューからの遷移（「他の言語…」→ Language タブ）に使う。
//

import Foundation
import Combine

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case language
    case about
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}
