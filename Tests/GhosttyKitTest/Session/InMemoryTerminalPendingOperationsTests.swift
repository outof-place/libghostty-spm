import Foundation
@testable import GhosttyTerminal
import Testing

struct InMemoryTerminalPendingOperationsTests {
    @Test
    func `entries come out in order across compactions`() {
        var queue = InMemoryTerminalPendingOperations()
        var expected = 0
        for value in 0 ..< 5000 {
            queue.append(.write(Data("\(value)".utf8), replay: false))
            if value % 3 == 0 {
                #expect(text(queue.popFirst()) == "\(expected)")
                expected += 1
            }
        }
        while let operation = queue.popFirst() {
            #expect(text(operation) == "\(expected)")
            expected += 1
        }
        #expect(expected == 5000)
        #expect(queue.isEmpty)
        #expect(queue.writeByteCount == 0)
    }

    @Test
    func `coalescing joins only consecutive writes`() {
        var queue = InMemoryTerminalPendingOperations()
        queue.appendCoalescing(Data("a".utf8))
        queue.appendCoalescing(Data("b".utf8))
        queue.append(.processExit(exitCode: 1, runtimeMilliseconds: 0))
        queue.appendCoalescing(Data("c".utf8))

        #expect(queue.count == 3)
        #expect(queue.writeByteCount == 3)
        #expect(text(queue.popFirst()) == "ab")
        #expect(text(queue.popFirst()) == "exit:1")
        #expect(text(queue.popFirst()) == "c")
        #expect(queue.popFirst() == nil)
    }

    @Test
    func `trimming drops the oldest bytes and keeps exits`() {
        var queue = InMemoryTerminalPendingOperations()
        queue.append(.write(Data("0123".utf8), replay: false))
        queue.append(.processExit(exitCode: 2, runtimeMilliseconds: 0))
        queue.append(.write(Data("4567".utf8), replay: false))
        queue.append(.write(Data("89".utf8), replay: false))

        queue.trimWrites(toLimit: 3)

        #expect(queue.writeByteCount == 3)
        #expect(queue.count == 3)
        #expect(text(queue.popFirst()) == "exit:2")
        #expect(text(queue.popFirst()) == "7")
        #expect(text(queue.popFirst()) == "89")
        #expect(queue.isEmpty)
    }

    private func text(_ operation: InMemoryTerminalPendingOperations.Operation?) -> String? {
        switch operation {
        case let .write(data, _)?:
            String(decoding: data, as: UTF8.self)
        case let .processExit(exitCode, _)?:
            "exit:\(exitCode)"
        case nil:
            nil
        }
    }
}

@Suite struct InMemoryTerminalReplayWriteTests {
    @Test func replayAndLiveWritesKeepTheirKindAndOrder() {
        var queue = InMemoryTerminalPendingOperations()
        queue.appendCoalescing(Data("seed".utf8), replay: true)
        queue.appendCoalescing(Data("-more".utf8), replay: true)
        queue.appendCoalescing(Data("live".utf8))
        #expect(queue.writeByteCount == 13)
        guard case let .write(seed, replay)? = queue.popFirst() else {
            Issue.record("expected the seed first")
            return
        }
        #expect(String(decoding: seed, as: UTF8.self) == "seed-more")
        #expect(replay)
        guard case let .write(live, liveReplay)? = queue.popFirst() else {
            Issue.record("expected live output second")
            return
        }
        #expect(String(decoding: live, as: UTF8.self) == "live")
        #expect(!liveReplay)
    }
}
