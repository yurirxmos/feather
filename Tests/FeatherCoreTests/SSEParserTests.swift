import XCTest
@testable import FeatherCore

final class SSEParserTests: XCTestCase {
    func testParsesEventAndData() {
        var parser = SSEParser()
        let events = parser.push("event: content_block_delta\ndata: {\"a\":1}\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "content_block_delta", data: "{\"a\":1}")])
    }

    func testHandlesChunksSplitMidLine() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("event: pi"), [])
        XCTAssertEqual(parser.push("ng\ndata: {\"te"), [])
        XCTAssertEqual(parser.push("xt\":\"hi\"}\n"), [SSEEvent(event: "ping", data: "{\"text\":\"hi\"}")])
    }

    func testHandlesCRLFAndComments() {
        var parser = SSEParser()
        let events = parser.push(": keep-alive\r\ndata: [DONE]\r\n\r\n")
        XCTAssertEqual(events, [SSEEvent(event: nil, data: "[DONE]")])
    }

    func testEventNameDoesNotLeakIntoNextEvent() {
        var parser = SSEParser()
        let events = parser.push("event: first\ndata: 1\n\ndata: 2\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "first", data: "1"), SSEEvent(event: nil, data: "2")])
    }

    func testFinishFlushesUnterminatedLine() {
        var parser = SSEParser()
        XCTAssertEqual(parser.push("data: tail"), [])
        XCTAssertEqual(parser.finish(), [SSEEvent(event: nil, data: "tail")])
    }
}
