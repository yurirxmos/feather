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

    public static func stream<Lines: AsyncSequence & Sendable>(
        lines: Lines,
        parse: @escaping @Sendable (SSEEvent) throws -> StreamChunk
    ) -> AsyncThrowingStream<String, Error> where Lines.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = SSEParser()
                    lineLoop: for try await line in lines {
                        for event in parser.push(line + "\n") {
                            switch try parse(event) {
                            case .text(let text): continuation.yield(text)
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
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
