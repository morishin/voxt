//
//  StatusIcon.swift
//  vkey
//
//  メニューバーに表示する状態アイコン。
//

import SwiftUI

struct StatusIcon: View {
    let state: PipelineStatusStore.UIState

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
    }

    private var symbolName: String {
        switch state {
        case .ready:
            return "mic"
        case .recording:
            return "mic.fill"
        case .processing:
            return "waveform"
        }
    }
}
