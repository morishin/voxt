//
//  SettingsNavigation.swift
//  Voxt
//
//  Shares the currently selected settings tab, used for navigation from the menu (e.g., "Other Languages…" → Language tab).
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
