//
//  PipelineCoordinator.swift
//  vkey
//
//  Intake のストリームを消費し、発話レベルの並列度を bounded-pump で制御しながら処理する。
//  各発話を processor で処理し、結果を InsertionSerializer へ渡す（順序保証はそちらが担う）。
//

import Foundation

actor PipelineCoordinator {
    private let processor: UtteranceProcessor
    private let serializer: InsertionSerializer
    private let configProvider: @Sendable () async -> ProcessingConfig

    init(processor: UtteranceProcessor,
         serializer: InsertionSerializer,
         configProvider: @escaping @Sendable () async -> ProcessingConfig) {
        self.processor = processor
        self.serializer = serializer
        self.configProvider = configProvider
    }

    /// ストリームを消費し、最大 maxConcurrentUtterances 件を同時処理する。
    func run(stream: AsyncStream<RawUtterance>, maxConcurrentUtterances: Int) async {
        let maxInFlight = max(1, maxConcurrentUtterances)
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = stream.makeAsyncIterator()

            // 上限まで埋め、1 件完了するたびに次を投入する bounded-pump。
            func pump() async {
                while inFlight < maxInFlight, let u = await iterator.next() {
                    inFlight += 1
                    group.addTask { [processor, serializer, configProvider] in
                        let config = await configProvider()
                        let result = await processor.process(u, config: config)
                        await serializer.deliver(result)
                    }
                }
            }

            await pump()
            for await _ in group {
                inFlight -= 1
                await pump()
            }
        }
    }
}
