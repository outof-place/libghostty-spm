#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
    @testable import GhosttyTerminal
    import Testing

    /// Paste, copy and OSC 52 through the view, on a pasteboard of the
    /// test's own (`pasteboardName`): the user's clipboard is never read or
    /// written.
    @Suite("AppTerminalViewPasteboard", .serialized)
    @MainActor
    struct AppTerminalViewPasteboardTests {
        static let commandV = Key(code: 9, characters: "v", ignoringModifiers: "v", flags: Key.leftCommand)

        /// 1,024 numbered lines of 64 bytes: 64 KiB.
        static let large = (0 ..< 1024).map { String(format: "%05d ", $0) + String(repeating: "x", count: 57) }
            .joined(separator: "\n") + "\n"

        @Test
        func `a large paste arrives whole inside one bracketed paste`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig()
            defer { rig.tearDown() }
            rig.receive("\u{1B}[?2004h")
            rig.pasteboard.clearContents()
            rig.pasteboard.setString(Self.large, forType: .string)
            #expect(Self.large.utf8.count == 65536)

            let clock = ContinuousClock()
            let started = clock.now
            rig.press(Self.commandV)
            let bytes = await rig.take()
            let elapsed = clock.now - started
            print("paste 64 KiB: \(bytes.count) bytes out in \(elapsed)")

            let start = Data("\u{1B}[200~".utf8), end = Data("\u{1B}[201~".utf8)
            #expect(bytes.starts(with: start))
            #expect(bytes.suffix(end.count) == end)
            #expect(bytes.count(of: "\u{1B}[200~") == 1)
            #expect(bytes.count(of: "\u{1B}[201~") == 1)
            let body = String(decoding: bytes.dropFirst(start.count).dropLast(end.count), as: UTF8.self)
            // Inside the brackets the text goes verbatim, newlines included.
            #expect(body == Self.large)
        }

        @Test
        func `an unsafe paste waits for the host`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig()
            defer { rig.tearDown() }
            let host = ConfirmationRecorder()
            rig.view.delegate = host

            // An end marker inside a bracketed paste would end it early.
            rig.receive("\u{1B}[?2004h")
            let marker = "safe\u{1B}[201~echo typed\n"
            rig.pasteboard.clearContents()
            rig.pasteboard.setString(marker, forType: .string)
            rig.press(Self.commandV)
            await LifecycleStress.drainMainQueue()
            #expect(host.requests.map(\.kind) == [.paste])
            #expect(host.requests.first?.contents == marker)
            host.requests.removeFirst().respond(allow: false)
            #expect(await rig.take().isEmpty)

            // Lines into a program without bracketed paste would run.
            rig.receive("\u{1B}[?2004l")
            rig.pasteboard.clearContents()
            rig.pasteboard.setString("echo one\necho two\n", forType: .string)
            rig.press(Self.commandV)
            await LifecycleStress.drainMainQueue()
            #expect(host.requests.map(\.kind) == [.paste])
            host.requests.removeFirst().respond(allow: true)
            #expect(await rig.take() == Data("echo one\recho two\r".utf8))

            // Without a host that answers, an unsafe paste is dropped.
            rig.view.delegate = nil
            rig.press(Self.commandV)
            await LifecycleStress.drainMainQueue()
            #expect(await rig.take().isEmpty)
        }

        @Test
        func `copy writes the selection to the view's pasteboard`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig()
            defer { rig.tearDown() }
            rig.receive("\u{1B}[2J\u{1B}[Hfirst line\r\nsecond line")

            #expect(rig.view.performBindingAction("select_all"))
            rig.view.copy(nil)
            #expect(rig.pasteboard.string(forType: .string) == "first line\nsecond line")
        }

        @Test
        func `a program's OSC 52 write lands on the view's pasteboard`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig()
            defer { rig.tearDown() }

            rig.receive("\u{1B}]52;c;\(Data("from the program".utf8).base64EncodedString())\u{07}")
            await LifecycleStress.drainMainQueue()
            #expect(rig.pasteboard.string(forType: .string) == "from the program")
        }
    }

    @MainActor
    final class ConfirmationRecorder: TerminalSurfaceClipboardConfirmationDelegate {
        var requests: [TerminalClipboardConfirmationRequest] = []

        func terminalDidRequestClipboardConfirmation(_ request: TerminalClipboardConfirmationRequest) {
            requests.append(request)
        }
    }
#endif
