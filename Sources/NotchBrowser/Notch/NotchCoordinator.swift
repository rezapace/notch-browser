import AppKit

/// Presentation policy for ONE panel that expands from and collapses into the notch.
@MainActor
final class NotchCoordinator: NSObject {
    private let window: WorkspaceWindow
    private let browser: BrowserController
    private var targetScreen: NSScreen?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var pointerInside = false
    private var hasInteracted = false
    private var requiresPointerExit = false
    private var isStopped = false

    init(window: WorkspaceWindow, browser: BrowserController) {
        self.window = window
        self.browser = browser
        super.init()
        window.onDismiss = { [weak self] in self?.dismiss() }
        window.onExpandRequested = { [weak self] in self?.show(activate: true) }
        browser.onDismissRequested = { [weak self] in self?.dismiss() }
        window.onInteraction = { [weak self] in
            self?.hasInteracted = true
            self?.closeWork?.cancel()
        }
        window.onHoverChanged = { [weak self] inside in self?.hoverChanged(inside) }
        NotificationCenter.default.addObserver(self, selector: #selector(didResignKey), name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func start() {
        targetScreen = preferredScreen()
        if let screen = targetScreen { window.showCompact(on: screen) }
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func hoverChanged(_ inside: Bool) {
        pointerInside = inside
        openWork?.cancel()
        if !inside { requiresPointerExit = false }
        guard !isStopped else { return }
        if !window.isPresented {
            guard inside, !requiresPointerExit, !window.isTransitioning else { return }
            let work = DispatchWorkItem { [weak self] in self?.show(activate: false) }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else if inside && !hasInteracted {
            closeWork?.cancel()
        } else if !inside {
            scheduleClose()
        }
    }

    /// Dock and clicks take focus; hover expands the same panel without activation.
    func show(activate: Bool) {
        guard !isStopped, let screen = targetScreen ?? preferredScreen() else { return }
        openWork?.cancel()
        closeWork?.cancel()
        if !window.isPresented { hasInteracted = false }
        requiresPointerExit = false
        window.present(on: screen, activate: activate)
        pointerInside = window.containsPointer
        browser.prepareForPresentation()
        if activate { browser.focusAddressIfHome() }
        // No travel timeout: compact and expanded regions are physically continuous.
        if !activate && !pointerInside { scheduleClose() }
    }

    @objc private func didBecomeKey() {
        hasInteracted = true
        closeWork?.cancel()
    }

    @objc private func didResignKey() {
        if window.isPresented { scheduleClose() }
    }

    private func scheduleClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped, self.window.isPresented,
                  WorkspacePolicy.canAutoDismiss(
                    isKey: self.window.isKeyWindow,
                    hasSheet: self.window.attachedSheet != nil,
                    pointerInside: self.pointerInside,
                    hasInteracted: self.hasInteracted
                  ) else { return }
            self.dismiss()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func dismiss() {
        guard window.isPresented else { return }
        openWork?.cancel()
        closeWork?.cancel()
        requiresPointerExit = true // Do not reopen immediately underneath a stationary cursor.
        browser.prepareForDismissal()
        window.dismiss { [weak self] in
            guard let self else { return }
            self.pointerInside = self.window.containsPointer
            if !self.pointerInside { self.requiresPointerExit = false }
        }
    }

    @objc private func screensChanged() {
        openWork?.cancel()
        closeWork?.cancel()
        targetScreen = preferredScreen()
        guard let screen = targetScreen else { window.orderOut(nil); return }
        window.reposition(on: screen)
        window.orderFrontRegardless()
        pointerInside = window.containsPointer
        browser.prepareForPresentation()
        if window.isPresented && !pointerInside { scheduleClose() }
    }

    func stop() {
        isStopped = true
        openWork?.cancel()
        closeWork?.cancel()
        browser.prepareForDismissal()
        window.orderOut(nil)
        NotificationCenter.default.removeObserver(self)
        window.onDismiss = nil
        window.onExpandRequested = nil
        window.onInteraction = nil
        window.onHoverChanged = nil
        browser.onDismissRequested = nil
    }
}
