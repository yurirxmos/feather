import Foundation

/// Consumes provider-neutral SSE lines; the URLSession adapter only supplies bytes and status.
public enum LLMStreamPump {
    public static func readErrorBody<Bytes: AsyncSequence & Sendable>(
        from bytes: Bytes,
        maximumBytes: Int = 64_000
    ) async throws -> Data where Bytes.Element == UInt8 {
        guard maximumBytes > 0 else { return Data() }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count >= maximumBytes { break }
        }
        return body
    }

    public static func httpError(statusCode: Int, body: Data, provider: any LLMProvider) -> LLMError {
        .http(status: statusCode, message: provider.errorMessage(fromBody: body))
    }

    /// How long the stream may stay silent after its first text before it is treated as
    /// finished. Guards against servers that never close the connection.
    public static let defaultIdleTimeout: Duration = .seconds(20)

    public static func stream<Lines: AsyncSequence & Sendable>(
        lines: Lines,
        idleTimeout: Duration = defaultIdleTimeout,
        parse: @escaping @Sendable (SSEEvent) throws -> StreamChunk
    ) -> AsyncThrowingStream<String, Error> where Lines.Element == String {
        AsyncThrowingStream { continuation in
            let activity = StreamActivity()
            let reader = Task {
                do {
                    var parser = SSEParser()
                    lineLoop: for try await line in lines {
                        for event in parser.push(line + "\n") {
                            switch try parse(event) {
                            case .text(let text):
                                activity.touch()
                                continuation.yield(text)
                            case .finalText(let text):
                                continuation.yield(text)
                                break lineLoop
                            case .done: break lineLoop
                            case .ignore: continue
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let watchdog = Task {
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    try? await Task.sleep(for: min(idleTimeout, .milliseconds(500)))
                    if let last = activity.lastText, clock.now - last >= idleTimeout {
                        reader.cancel()
                        continuation.finish()
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                watchdog.cancel()
            }
        }
    }
}

/// When the stream last produced text; read by the idle watchdog.
private final class StreamActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var last: ContinuousClock.Instant?

    var lastText: ContinuousClock.Instant? {
        lock.withLock { last }
    }

    func touch() {
        lock.withLock { last = ContinuousClock.now }
    }
}
