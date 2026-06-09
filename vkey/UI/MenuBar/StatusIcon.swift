//
//  StatusIcon.swift
//  vkey
//
//  メニューバーに表示する状態アイコン。
//  MenuBarExtra のラベルは symbolEffect が効かないため、blinkOn の反転で点滅させる。
//

import SwiftUI

struct StatusIcon: View {
    let state: PipelineStatusStore.UIState
    /// 点滅フラグ（PipelineStatusStore が Timer で反転）。
    var blinkOn: Bool = true

    var body: some View {
        switch state {
        case .ready:
            Image(systemName: "mic")
                .symbolRenderingMode(.hierarchical)
        case .recording:
            // 録音中: 塗り↔輪郭でハッキリ点滅。
            Image(systemName: blinkOn ? "mic.fill" : "mic")
                .symbolRenderingMode(.hierarchical)
        case .processing:
            // 処理中: 波形を薄く↔濃く点滅。
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
                .opacity(blinkOn ? 1.0 : 0.4)
        }
    }
}
