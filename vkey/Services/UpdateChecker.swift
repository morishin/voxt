//
//  UpdateChecker.swift
//  vkey
//
//  GitHub Releases の最新版を取得し、現在のバージョンと比較してアップデートの有無を判定する。
//  releases/latest への HEAD リクエストはタグページ（/releases/tag/vX.Y）へリダイレクトされるので、
//  リダイレクト先 URL の末尾からバージョン文字列を取り出して比較する（XDeck と同じ手法）。
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

    /// 最新リリースを指す URL。リポジトリを変えたらここを更新する。
    private let latestReleaseURL = URL(string: "https://github.com/morishin/voxt/releases/latest")!

    func check() async {
        status = .checking

        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "HEAD"

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let finalURL = response.url else {
            // ネットワークエラー等。黙って初期状態に戻し、再度確認できるようにする。
            status = .idle
            return
        }

        // 末尾の "v" を取り除いてバージョン番号だけにする（例: "v1.2" → "1.2"）。
        let remoteVersion = finalURL.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
            status = .available(finalURL)
        } else {
            status = .upToDate
        }
    }
}
