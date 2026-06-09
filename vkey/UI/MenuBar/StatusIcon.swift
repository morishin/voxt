//
//  StatusIcon.swift
//  vkey
//
//  メニューバーに表示する状態アイコン。
//  録音中はパルス点滅、処理中は波形を可変カラーでアニメーションさせる。
//

import SwiftUI

struct StatusIcon: View {
    let state: PipelineStatusStore.UIState

    var body: some View {
        switch state {
        case .ready:
            Image(systemName: "mic")
                .symbolRenderingMode(.hierarchical)
        case .recording:
            // 録音中: パルス点滅（繰り返し）。
            Image(systemName: "mic.fill")
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating)
        case .processing:
            // 処理中: 波形を順番に光らせて「動いている」感を出す。
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.variableColor.iterative.hideInactiveLayers, options: .repeating)
        }
    }
}
