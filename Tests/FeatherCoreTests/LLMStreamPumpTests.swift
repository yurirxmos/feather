import XCTest
@testable import FeatherCore

final class LLMStreamPumpTests: XCTestCase {
    func testPumpEmitsTextAndStopsAtDone() async throws {
        let lines = AsyncStream<String> { continuation in
            continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
            continuation.yield("")
            continuation.yield("data: [DONE]")
            continuation.yield("")
            continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\"ignored\"}}]}")
            continuation.finish()
        }
        let output = LLMStreamPump.stream(lines: lines) { event in
            try OpenCodeGoProvider(apiKey: "key").parse(event)
        }
        var result: [String] = []
        for try await text in output { result.append(text) }
        XCTAssertEqual(result, ["Hello"])
    }

    func testPumpStopsAtFinishReasonWhenTheServerKeepsTheConnectionOpen() async throws {
        let lines = AsyncStream<String> { continuation in
            continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
            continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]}")
            continuation.yield(": keep-alive")
            // Never finishes, like a server that leaves the connection open.
        }
        let output = LLMStreamPump.stream(lines: lines) { event in
            try OpenCodeGoProvider(apiKey: "key").parse(event)
        }
        var result: [String] = []
        for try await text in output { result.append(text) }
        XCTAssertEqual(result, ["Hello", " world"])
    }

    func testPumpFinishesWhenTheStreamGoesIdleAfterText() async throws {
        let lines = AsyncStream<String> { continuation in
            continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
        }
        let output = LLMStreamPump.stream(lines: lines, idleTimeout: .milliseconds(100)) { event in
            try OpenCodeGoProvider(apiKey: "key").parse(event)
        }
        var result: [String] = []
        for try await text in output { result.append(text) }
        XCTAssertEqual(result, ["Hello"])
    }

    func testPumpPropagatesProviderErrors() async {
        let lines = AsyncStream<String> { continuation in
            continuation.yield("data: {\"error\":{\"message\":\"rejected\"}}")
            continuation.yield("")
            continuation.finish()
        }
        let output = LLMStreamPump.stream(lines: lines) { event in
            try OpenCodeGoProvider(apiKey: "key").parse(event)
        }
        do {
            for try await _ in output {}
            XCTFail("Expected provider error")
        } catch {
            XCTAssertEqual(error as? LLMError, .api(message: "rejected"))
        }
    }

    func testLimitKeepsTextAndFailsWithTimeoutAtTheDeadline() async {
        let source = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("Hello")
            // Never finishes, like a model that keeps the request open.
        }
        var result: [String] = []
        do {
            for try await text in LLMStreamPump.limit(source, to: .milliseconds(100)) { result.append(text) }
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? LLMError, .timedOut)
        }
        XCTAssertEqual(result, ["Hello"])
    }

    func testLimitPassesThroughAStreamThatFinishesInTime() async throws {
        let source = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("Hello")
            continuation.finish()
        }
        var result: [String] = []
        for try await text in LLMStreamPump.limit(source, to: .seconds(5)) { result.append(text) }
        XCTAssertEqual(result, ["Hello"])
    }

    func testErrorBodyReaderEnforcesByteLimit() async throws {
        let bytes = AsyncStream<UInt8> { continuation in
            for _ in 0..<100 { continuation.yield(0x78) }
            continuation.finish()
        }
        let body = try await LLMStreamPump.readErrorBody(from: bytes, maximumBytes: 32)
        XCTAssertEqual(body.count, 32)
    }

    func testHTTPErrorUsesSharedProviderMessageParser() {
        let provider = OpenCodeGoProvider(apiKey: "key")
        let error = LLMStreamPump.httpError(
            statusCode: 429,
            body: Data(#"{"error":{"message":"slow down"}}"#.utf8),
            provider: provider
        )
        XCTAssertEqual(error, .http(status: 429, message: "slow down"))
    }
}
