//
//  IconAnimator.swift
//  vkey
//
//  メニューバーアイコンの滑らかなパルスアニメーション駆動。
//  MenuBarExtra のラベルは symbolEffect が効かないため、高頻度 Timer(~20fps)で
//  opacity 値を sin 波で連続的に更新し、コマ送りで滑らかにフェードさせる。
//  高頻度更新がメニュー本体へ波及しないよう、状態ストアから分離した専用 ObservableObject。
//

import Foundation
import Combine

@MainActor
final class IconAnimator: ObservableObject {

    /// 0...1 のパルス値（opacity 等にマッピングして使う）。
    @Published private(set) var pulse: Double = 1.0

    private var timer: Timer?
    private var phase: Double = 0
    /// 更新間隔（約 20fps）。
    private let frameInterval: TimeInterval = 1.0 / 20.0
    /// 1 呼吸の周期（秒）。
    private let period: TimeInterval = 1.6

    /// アニメーションの開始/停止。停止時は点灯（pulse=1）に戻す。
    func setAnimating(_ animating: Bool) {
        if animating {
            guard timer == nil else { return }
            phase = 0
            let timer = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            phase = 0
            if pulse != 1.0 { pulse = 1.0 }
        }
    }

    private func tick() {
        phase += frameInterval
        // sin を 0...1 に正規化した滑らかな呼吸カーブ。
        pulse = (sin(phase * 2 * .pi / period) + 1) / 2
    }
}
