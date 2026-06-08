//
//  UpdateChecker.swift
//  Voxt
//
//  Fetches the latest release from GitHub Releases and compares it to the current version
//  to determine whether an update is available. A HEAD request to releases/latest redirects
//  to the tag page (/releases/tag/vX.Y), so the version string is extracted from the end of
//  the redirect URL for comparison (same technique as XDeck).
//

import Foundation
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    enum Status {
        case idle
        case checking
        case upToDate
        case available(URL)
    }

    @Published var status: Status = .idle

    /// URL pointing to the latest release. Update this if the repository changes.
    private let latestReleaseURL = URL(string: "https://github.com/morishin/voxt/releases/latest")!

    func check() async {
        status = .checking

        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "HEAD"

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let finalURL = response.url else {
            // Network error or similar. Silently revert to idle so the user can try again.
            status = .idle
            return
        }

        // Strip the leading "v" to get just the version number (e.g. "v1.2" → "1.2").
        let remoteVersion = finalURL.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
            status = .available(finalURL)
        } else {
            status = .upToDate
        }
    }
}
