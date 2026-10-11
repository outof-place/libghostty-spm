#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
    @testable import GhosttyTerminal
    import Testing

    /// Dead keys and input methods through `NSTextInputClient`: a composition
    /// shows as ghostty's preedit and sends nothing, and only the committed
    /// text reaches the program, typed (key path), even with bracketed paste
    /// on. The input method is a script (``ScriptedInputView``), so the
    /// tests never touch the Mac's input source.
    @Suite("AppTerminalViewMarkedText", .serialized)
    @MainActor
    struct AppTerminalViewMarkedTextTests {
        static let bracketedPasteOn = "\u{1B}[?2004h"

        @Test
        func `a dead key composes and only the letter is typed`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let view = ScriptedInputView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
            let rig = AppKitInputRig(view: view, optionAsAlt: "false")
            defer { rig.tearDown() }
            rig.receive(Self.bracketedPasteOn)
            // Option+E then E on a US layout: the accent waits as marked text.
            view.script = { event, view in
                if event.modifierFlags.contains(.option) {
                    view.mark("´")
                } else {
                    view.commit("é")
                }
            }

            rig.press(Key.letter("e", code: 14).with(Key.leftOption, characters: ""))
            #expect(view.hasMarkedText())
            #expect(await rig.take().isEmpty)

            rig.press(Key.letter("e", code: 14))
            #expect(!view.hasMarkedText())
            #expect(await rig.take() == Data("é".utf8))
        }

        @Test
        func `an input method composition sends only its committed text`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let view = ScriptedInputView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
            let rig = AppKitInputRig(view: view)
            defer { rig.tearDown() }
            rig.receive(Self.bracketedPasteOn + "\u{1B}[>5u")
            // Kana input: k, a, Space to convert, Return to commit.
            var marked = ""
            view.script = { event, view in
                switch event.characters {
                case "k": marked = "k"; view.mark(marked)
                case "a": marked = "か"; view.mark(marked)
                case " ": marked = "下"; view.mark(marked)
                case "\r": view.commit(marked)
                default: break
                }
            }

            for key in [Key.letter("k", code: 40), Key.letter("a", code: 0), Key(code: 49, characters: " ", ignoringModifiers: " ")] {
                rig.press(key)
                #expect(view.hasMarkedText())
                #expect(await rig.take().isEmpty, "a composing key sent bytes")
            }
            let caret = view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
            #expect(caret.width > 0 && caret.height > 0, "the candidate window has no place")

            // The Return that commits is the input method's, not the shell's.
            rig.press(.returnKey)
            #expect(!view.hasMarkedText())
            #expect(await rig.take() == Data("下".utf8))
        }

        @Test
        func `a commit from the candidate window arrives as a paste`() async {
            let harness = await GhosttySurfaceHarness.make()
            defer { harness.tearDown() }
            let view = ScriptedInputView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
            let rig = AppKitInputRig(view: view)
            defer { rig.tearDown() }
            rig.receive(Self.bracketedPasteOn)

            view.mark("かんじ")
            #expect(await rig.take().isEmpty)
            // A click in the candidate list: no key event is in progress.
            rig.during(rig.mouse(.leftMouseDown, at: .zero)) {
                view.commit("漢字")
            }
            #expect(!view.hasMarkedText())
            // Upstream's text path for an `insertText` outside a key press.
            #expect(await rig.take() == Data("\u{1B}[200~漢字\u{1B}[201~".utf8))
        }
    }
#endif
