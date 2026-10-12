#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
    @testable import GhosttyTerminal
    import Testing

    /// Ghostty's pointer settings in the AppKit view: the selection clipboard
    /// a middle click pastes, `mouse-hide-while-typing` and
    /// `focus-follows-mouse`. Events go straight to the view; no window is
    /// ever shown, and the user's clipboard is never read or written.
    @Suite("AppTerminalViewPointerSettings", .serialized)
    @MainActor
    struct AppTerminalViewPointerSettingsTests {
        @Test
        func `a middle click pastes the last selection, never the clipboard`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig(config: [("copy-on-select", "primary")])
            defer { rig.tearDown() }
            rig.receive("\u{1B}[?2004h\u{1B}[2J\u{1B}[Hselected words")
            rig.pasteboard.setString("from the clipboard", forType: .string)

            #expect(rig.view.performBindingAction("select_all"))
            await LifecycleStress.drainMainQueue()
            let at = rig.location(col: 2, row: 3)
            rig.view.otherMouseDown(with: rig.mouse(.otherMouseDown, at: at))
            rig.view.otherMouseUp(with: rig.mouse(.otherMouseUp, at: at))
            #expect(await rig.take() == Data("\u{1B}[200~selected words\u{1B}[201~".utf8))
            // The selection never reached the pasteboard.
            #expect(rig.pasteboard.string(forType: .string) == "from the clipboard")
        }

        @Test
        func `a middle click with nothing selected pastes nothing`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig(config: [("copy-on-select", "primary")])
            defer { rig.tearDown() }
            rig.receive("\u{1B}[?2004h")
            rig.pasteboard.setString("from the clipboard", forType: .string)

            let at = rig.location(col: 2, row: 3)
            rig.view.otherMouseDown(with: rig.mouse(.otherMouseDown, at: at))
            rig.view.otherMouseUp(with: rig.mouse(.otherMouseUp, at: at))
            #expect(await rig.take().isEmpty)
        }

        @Test
        func `typing hides the pointer and moving the mouse shows it`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let view = PointerVisibilityRecorder(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
            let rig = AppKitInputRig(view: view, config: [("mouse-hide-while-typing", "true")])
            defer { rig.tearDown() }

            rig.press(.letter("a", code: 0))
            await LifecycleStress.drainMainQueue()
            #expect(view.visibility == [false])
            rig.view.mouseMoved(with: rig.mouse(.mouseMoved, at: rig.location(col: 4, row: 2)))
            await LifecycleStress.drainMainQueue()
            #expect(view.visibility == [false, true])
        }

        @Test
        func `typing leaves the pointer alone by default`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let view = PointerVisibilityRecorder(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
            let rig = AppKitInputRig(view: view)
            defer { rig.tearDown() }

            rig.press(.letter("a", code: 0))
            await LifecycleStress.drainMainQueue()
            #expect(view.visibility.isEmpty)
        }

        @Test(arguments: [true, false])
        func `the pointer moves the keyboard to the terminal only with focus-follows-mouse`(follows: Bool) async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let rig = AppKitInputRig(config: [("focus-follows-mouse", "\(follows)")], keyWindow: true)
            defer { rig.tearDown() }
            #expect(rig.view.controller?.focusFollowsMouse == follows)
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
            rig.view.addSubview(field)
            rig.window.makeFirstResponder(field)
            #expect(rig.window.firstResponder !== rig.view)

            rig.view.mouseMoved(with: rig.mouse(.mouseMoved, at: rig.location(col: 10, row: 5)))
            #expect((rig.window.firstResponder === rig.view) == follows)
        }
    }

    final class PointerVisibilityRecorder: AppTerminalView {
        var visibility: [Bool] = []

        override func terminalMouseVisibilityDidChange(visible: Bool) {
            visibility.append(visible)
        }
    }
#endif
