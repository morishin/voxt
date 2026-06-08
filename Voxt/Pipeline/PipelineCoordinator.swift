//
//  PipelineCoordinator.swift
//  Voxt
//
//  Consumes the Intake stream, processing each utterance while controlling utterance-level
//  concurrency via a bounded-pump. Each utterance is processed by the processor and its
//  result is handed off to InsertionSerializer (which is responsible for ordering guarantees).
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

    /// Consumes the stream and processes up to maxConcurrentUtterances utterances concurrently.
    func run(stream: AsyncStream<RawUtterance>, maxConcurrentUtterances: Int) async {
        let maxInFlight = max(1, maxConcurrentUtterances)
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = stream.makeAsyncIterator()

            // Bounded-pump: fills up to the limit, then submits the next item each time one completes.
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
