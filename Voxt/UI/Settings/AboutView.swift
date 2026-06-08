//
//  AboutView.swift
//  Voxt
//
//  The "About" tab in the Settings window. Displays the app name, version, update check, author info, and donation link.
//

import SwiftUI
import AppKit

struct AboutView: View {
    @StateObject private var checker = UpdateChecker()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// The app icon shown in the About view.
    /// `NSApp.applicationIconImage` can return a design-grid placeholder for accessory apps
    /// using the new `.icon` (Liquid Glass) format when not registered with LaunchServices,
    /// so we load the bundled `.icns` (CFBundleIconFile) directly. Falls back to the legacy API if unavailable.
    private static var appIconImage: NSImage {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
           let url = Bundle.main.url(forResource: name, withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: Self.appIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Voxt")
                    .font(.title.bold())
                Text(String(format: String(localized: "Version %@"), version))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            updateSection

            Divider()

            VStack(spacing: 12) {
                LabeledContent(String(localized: "Author")) {
                    Link("morishin", destination: URL(string: "https://github.com/sponsors/morishin?frequency=one-time")!)
                }
                .frame(maxWidth: 240)

                Link(destination: URL(string: "https://github.com/sponsors/morishin?frequency=one-time")!) {
                    Label(String(localized: "Buy me a coffee"), systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await checker.check() }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch checker.status {
        case .idle:
            Button(String(localized: "Check for Updates")) {
                Task { await checker.check() }
            }
        case .checking:
            ProgressView(String(localized: "Checking…"))
                .controlSize(.small)
        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Up to date")
                    .foregroundStyle(.secondary)
                Button(String(localized: "Check for Updates")) {
                    Task { await checker.check() }
                }
                .buttonStyle(.link)
            }
            .font(.callout)
        case .available(let url):
            Link(destination: url) {
                Label(String(localized: "Update Available"), systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
