import Foundation

/// Stateful parser for streamed LLM text that may contain `<think>...</think>`
/// reasoning blocks (the format MiniMax-M2.7 uses).
///
/// We can't tell whether a chunk that ends in `<th` is the start of `<think>`
/// or just literal text, so we hold back the last 8 chars (length of
/// `</think>`) until the next chunk arrives. The cost is up to 8 characters
/// of latency between server send and UI display, which is invisible.
final class StreamParser: @unchecked Sendable {
    enum State: Sendable { case answer, inThinking }
    private let lock = NSLock()
    private var state: State = .answer
    private var buffer: String = ""

    private static let openTag = "<think>"
    private static let closeTag = "</think>"
    private static let maxMarkerLen = max(openTag.count, closeTag.count)

    /// Feed a chunk of streamed text. Returns the (thinkingDelta, contentDelta)
    /// to add to the message fields.
    func feed(_ chunk: String) -> (thinking: String, content: String) {
        lock.lock(); defer { lock.unlock() }
        buffer += chunk
        var thinkingDelta = ""
        var contentDelta = ""

        // Process any complete markers in the buffer (greedy, left-to-right)
        while let range = nextMarkerRange(in: buffer) {
            let pre = String(buffer[..<range.lowerBound])
            switch state {
            case .answer:     contentDelta += pre
            case .inThinking: thinkingDelta += pre
            }
            let marker = String(buffer[range])
            switch marker {
            case Self.openTag:  state = .inThinking
            case Self.closeTag: state = .answer
            default: break
            }
            buffer = String(buffer[range.upperBound...])
        }

        // Hold back the last `maxMarkerLen` chars as a possible partial marker.
        // Anything before that is safe to flush.
        if buffer.count > Self.maxMarkerLen {
            let safeCut = buffer.count - Self.maxMarkerLen
            let safeEnd = buffer.index(buffer.startIndex, offsetBy: safeCut)
            let flushable = String(buffer[..<safeEnd])
            switch state {
            case .answer:     contentDelta += flushable
            case .inThinking: thinkingDelta += flushable
            }
            buffer = String(buffer[safeEnd...])
        }

        return (thinkingDelta, contentDelta)
    }

    /// Call when the stream ends. Flushes whatever's still in the buffer into
    /// the current mode (in case a tag was split across chunks).
    func flush() -> (thinking: String, content: String) {
        lock.lock(); defer { lock.unlock() }
        var thinkingDelta = ""
        var contentDelta = ""
        switch state {
        case .answer:     contentDelta += buffer
        case .inThinking: thinkingDelta += buffer
        }
        buffer = ""
        return (thinkingDelta, contentDelta)
    }

    /// Find the earliest `<think>` or `</think>` range in the buffer.
    private func nextMarkerRange(in s: String) -> Range<String.Index>? {
        let open = s.range(of: Self.openTag)
        let close = s.range(of: Self.closeTag)
        switch (open, close) {
        case (nil, nil):   return nil
        case (let o?, nil): return o
        case (nil, let c?): return c
        case (let o?, let c?): return o.lowerBound < c.lowerBound ? o : c
        }
    }
}
