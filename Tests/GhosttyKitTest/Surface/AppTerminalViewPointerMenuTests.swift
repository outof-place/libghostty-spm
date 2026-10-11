#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
    import GhosttyKit
    @testable import GhosttyTerminal
    import Testing

    /// ⌘-click on what ghostty recognizes as a link, and the right-click menu.
    /// No menu is ever popped up: the tests read `menu(for:)` and ghostty's
    /// answer to the press that decides whether AppKit would show it.
    @Suite("AppTerminalViewPointerMenu", .serialized)
    @MainActor
    struct AppTerminalViewPointerMenuTests {
        @Test
        func `command-click hands links, OSC 8 targets and file:line paths to the host`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig()
            defer { rig.tearDown() }
            let links = LinkRecorder()
            rig.view.delegate = links
            let lines = [
                "see https://example.com/a?b=1 here",
                "\u{1B}]8;;https://pod.codes/osc8\u{1B}\\osc eight\u{1B}]8;;\u{1B}\\ text",
                "at src/foo.swift:12 end",
                "at /tmp/abs/foo.swift:12:3 end",
                "at ./rel/bar.ts:7 end",
                "file:///tmp/x.txt plain",
            ]
            rig.receive("\u{1B}[2J\u{1B}[H" + lines.joined(separator: "\r\n"))

            let expected = [
                (0, 8, "https://example.com/a?b=1"),
                (1, 2, "https://pod.codes/osc8"),
                (2, 5, "src/foo.swift:12"),
                (3, 6, "/tmp/abs/foo.swift:12:3"),
                (4, 5, "./rel/bar.ts:7"),
                (5, 3, "file:///tmp/x.txt"),
            ]
            for (row, col, url) in expected {
                links.opened = []
                rig.commandClick(col: col, row: row)
                await LifecycleStress.drainMainQueue()
                #expect(links.hovered == url, "row \(row) hover")
                #expect(links.opened == [url], "row \(row)")
            }

            // Plain words are no link.
            links.opened = []
            rig.commandClick(col: 1, row: 0)
            await LifecycleStress.drainMainQueue()
            #expect(links.opened.isEmpty)
        }

        @Test
        func `the context menu offers copy only with a selection`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig()
            defer { rig.tearDown() }
            rig.receive("\u{1B}[2J\u{1B}[Hsome output")
            let click = rig.mouse(.rightMouseDown, at: rig.location(col: 2, row: 0))

            #expect(rig.view.menu(for: click)?.items.map(\.title) == ["Paste", "Select All"])
            #expect(rig.view.performBindingAction("select_all"))
            let menu = rig.view.menu(for: click)
            #expect(menu?.items.map(\.title) == ["Copy", "Paste", "Select All"])
            #expect(menu?.items.allSatisfy { $0.target === rig.view } == true)
        }

        @Test
        func `a right press opens the menu only when the program does not take it`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig()
            defer { rig.tearDown() }
            let surface = rig.view.surface

            rig.view.mouseMoved(with: rig.mouse(.mouseMoved, at: rig.location(col: 2, row: 2)))
            #expect(surface?.sendMouseButton(state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT) == false)
            surface?.sendMouseButton(state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)

            // A program reporting the mouse (Claude Code's fullscreen view).
            rig.receive("\u{1B}[?1000h\u{1B}[?1006h")
            #expect(surface?.sendMouseButton(state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT) == true)
            surface?.sendMouseButton(state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
            #expect(String(decoding: await rig.take(), as: UTF8.self).contains("\u{1B}[<2;"))
        }
    }

    @MainActor
    final class LinkRecorder: TerminalSurfaceOpenURLDelegate, TerminalSurfaceHoverLinkDelegate {
        var opened: [String] = []
        var hovered: String?

        func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
            opened.append(url)
        }

        func terminalDidUpdateHoverLink(_ url: String?) {
            hovered = url
        }
    }
#endif
