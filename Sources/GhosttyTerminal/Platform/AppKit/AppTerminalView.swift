//
//  AppTerminalView.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/16.
//

#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
    import DisplayLink
    import GhosttyKit

    @MainActor
    open class AppTerminalView: NSView {
        let core = TerminalSurfaceCoordinator()
        var metalLayer: CAMetalLayer?
        var inputHandler: TerminalKeyEventHandler?

        // Grouped view state, one struct per concern — same convention as
        // the UIKit twin: each state type is defined in the extension file
        // that owns the behavior (+Input, +Lifecycle); the storage lives
        // here because extensions cannot add stored properties.
        var keyEcho: KeyEchoState = .init()
        var pointer: PointerSelectionState = .init()
        var focusBridge: FocusBridgeState = .init()
        var drop: DropState = .init()

        open weak var delegate: (any TerminalSurfaceViewDelegate)? {
            get { core.delegate }
            set { core.delegate = newValue }
        }

        open var controller: TerminalController? {
            get { core.controller }
            set { core.controller = newValue }
        }

        open var configuration: TerminalSurfaceOptions {
            get { core.configuration }
            set { core.configuration = newValue }
        }

        /// Where Copy writes and Paste reads, a program's OSC 52 included:
        /// the general pasteboard unless the host names its own (tests use a
        /// private one so they never touch the user's clipboard).
        open var pasteboardName: NSPasteboard.Name {
            get { core.bridge.pasteboardName }
            set { core.bridge.pasteboardName = newValue }
        }

        open func setSurfaceVisible(_ visible: Bool) {
            core.setDisplayVisible(visible)
        }

        /// Adjusts this surface's resize coalescing window without rebuilding
        /// it. Overrides `TerminalSurfaceOptions.resizeThrottleMilliseconds`,
        /// which is the declarative home for the same policy and the one every
        /// platform can reach; pass `nil` to fall back to it.
        open func setResizeThrottle(milliseconds: Double?) {
            core.resizeThrottleInterval = milliseconds.map { max(0, $0) / 1000 }
        }

        var surface: TerminalSurface? {
            core.surface
        }

        override public init(frame: NSRect) {
            super.init(frame: frame)
            commonInit()
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func commonInit() {
            wantsLayer = true

            let metal = CAMetalLayer()
            metal.device = MTLCreateSystemDefaultDevice()
            metal.pixelFormat = .bgra8Unorm
            metal.framebufferOnly = true
            metal.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            metal.isOpaque = false
            metal.backgroundColor = NSColor.clear.cgColor
            layer = metal
            metalLayer = metal
            layer?.backgroundColor = NSColor.clear.cgColor

            inputHandler = TerminalKeyEventHandler(view: self)
            setupTrackingArea()
            setupDropInput()

            core.isAttached = { [weak self] in self?.window != nil }
            core.displayLinkContext = .view(self)
            core.scaleFactor = { [weak self] in
                self?.currentScaleFactor() ?? 2.0
            }
            core.viewSize = { [weak self] in
                guard let self else { return (0, 0) }
                return (bounds.width, bounds.height)
            }
            core.platformSetup = { [weak self] config in
                guard let self else { return }
                config.platform_tag = GHOSTTY_PLATFORM_MACOS
                config.platform = ghostty_platform_u(
                    macos: ghostty_platform_macos_s(
                        nsview: Unmanaged.passUnretained(self).toOpaque(),
                    ),
                )
            }
            core.onMetricsUpdate = { [weak self] in
                self?.updateMetalLayerMetrics()
            }
            core.onPostRender = { [weak self] in
                self?.enforceMetalLayerScale()
            }
        }

        /// Upstream's rule: Copy is offered whenever ghostty has a selection.
        /// A cached drag rect went stale on scroll and select_all, and the
        /// quicklook-word test misses whitespace inside a selection.
        open func selectionMenuPoint(at point: CGPoint) -> CGPoint? {
            guard surface?.hasSelection() == true else {
                TerminalDebugLog.log(
                    .input,
                    "selection menu miss point=\(selectionPointDescription(point))",
                )
                return nil
            }

            TerminalDebugLog.log(
                .input,
                "selection menu hit point=\(selectionPointDescription(point))",
            )
            return point
        }

        open func selectionContextMenu() -> NSMenu {
            let menu = NSMenu()
            let copyItem = NSMenuItem(
                title: String(localized: "Copy", bundle: .module),
                action: #selector(copy(_:)),
                keyEquivalent: "",
            )
            copyItem.target = self
            menu.addItem(copyItem)
            return menu
        }

        /// The right-click menu: Copy while ghostty has a selection, then
        /// Paste and Select All. It opens on a right click inside a
        /// selection, and on one the program did not take (no mouse
        /// reporting) — upstream's rule. Hosts add their own items to it.
        open func terminalContextMenu() -> NSMenu {
            let menu = surface?.hasSelection() == true ? selectionContextMenu() : NSMenu()
            for (title, action) in [
                (String(localized: "Paste", bundle: .module), #selector(paste(_:))),
                (String(localized: "Select All", bundle: .module), #selector(selectAll(_:))),
            ] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            return menu
        }

        @discardableResult
        open func copySelectedTextToPasteboard() -> Bool {
            guard surface?.hasSelection() == true else {
                return false
            }
            guard surface?.performBindingAction("copy_to_clipboard") == true else {
                return false
            }
            TerminalDebugLog.log(
                .input,
                "selection copied to clipboard",
            )
            return true
        }

        private func selectionPointDescription(_ point: CGPoint) -> String {
            "\(String(format: "%.2f", point.x))x\(String(format: "%.2f", point.y))"
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
#endif
