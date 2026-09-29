import Foundation

public struct SSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

/// Incremental server-sent events parser. Feed it arbitrary chunks, split anywhere; it emits one
/// event per completed `data:` line, tagged with the preceding `event:` name.
public struct SSEParser {
    private var buffer = ""
    private var eventName: String?
    private var dataLines: [String] = []

    public init() {}

    public mutating func push(_ chunk: String) -> [SSEEvent] {
        buffer += chunk
        var events: [SSEEvent] = []
        while let newline = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let event = consume(line) { events.append(event) }
        }
        return events
    }

    /// Emits any event left open when the stream ends without a trailing blank line.
    public mutating func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []
        if !buffer.isEmpty, let event = consume(buffer) { events.append(event) }
        buffer = ""
        if let event = dispatch() { events.append(event) }
        return events
    }

    private mutating func consume(_ line: String) -> SSEEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event":
            eventName = String(value)
        case "data":
            dataLines.append(String(value))
            // `URLSession.AsyncBytes.lines` drops blank lines, so an event would otherwise never
            // be dispatched. Every provider we talk to sends one JSON object per `data:` line,
            // so dispatching eagerly is safe.
            return dispatch()
        default:
            break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            eventName = nil
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }
}
