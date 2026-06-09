//
//  StatusIcon.swift
//  vkey
//
//  メニューバーに表示する状態アイコン。
//  MenuBarExtra のラベルは symbolEffect が効かないため、IconAnimator の pulse(0...1)を
//  opacity にマッピングして滑らかに明滅させる。
//

import SwiftUI

struct StatusIcon: View {
    let state: PipelineStatusStore.UIState
    /// 0...1 のパルス値（IconAnimator が高頻度更新）。
    var pulse: Double = 1.0

    var body: some View {
        switch state {
        case .ready:
            Image(systemName: "mic")
                .symbolRenderingMode(.hierarchical)
        case .recording:
            Image(systemName: "mic.fill")
                .symbolRenderingMode(.hierarchical)
                .opacity(opacity)
        case .processing:
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
                .opacity(opacity)
        }
    }

    /// pulse(0...1) を 0.3...1.0 の opacity へマッピング。
    private var opacity: Double {
        0.3 + 0.7 * pulse
    }
}
