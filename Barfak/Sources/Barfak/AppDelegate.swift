import AppKit
import ServiceManagement
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [NSWindow] = []
    private let snowman = SnowmanController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Barfak") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "❄︎"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: Settings.didChange, object: nil)

        rebuildOverlays()
        settingsChanged()
    }

    // MARK: Overlay windows

    @objc private func screensChanged() { rebuildOverlays() }

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: screen.frame.size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true          // clicks go straight through
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                         .fullScreenAuxiliary, .ignoresCycle]
            window.setFrame(screen.frame, display: false)

            let view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.allowsTransparency = true
            view.ignoresSiblingOrder = true
            view.preferredFramesPerSecond = 60
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            view.presentScene(SnowScene(screenFrame: screen.frame))

            overlays.append(window)
        }
        applyPaused()
    }

    private func applyPaused() {
        let paused = Settings.shared.paused
        for window in overlays {
            (window.contentView as? SKView)?.isPaused = paused
            if paused { window.orderOut(nil) } else { window.orderFrontRegardless() }
        }
    }

    @objc private func settingsChanged() {
        applyPaused()
        snowman.setVisible(Settings.shared.snowman && !Settings.shared.paused)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = Settings.shared
        menu.removeAllItems()

        menu.addItem(item(s.paused ? "ادامه بارش برف" : "توقف بارش برف",
                          #selector(togglePaused), key: "p"))
        menu.addItem(.separator())

        let intensity = NSMenuItem(title: "شدت بارش", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, title) in ["کم", "متوسط", "زیاد"].enumerated() {
            let it = item(title, #selector(setIntensity(_:)))
            it.tag = i
            it.state = s.intensity == i ? .on : .off
            sub.addItem(it)
        }
        intensity.submenu = sub
        menu.addItem(intensity)

        menu.addItem(item("باد", #selector(toggleWind), on: s.wind))
        menu.addItem(item("نشستن برف روی پنجره‌ها", #selector(toggleAccumulate), on: s.accumulate))
        menu.addItem(item("آدم‌برفی", #selector(toggleSnowman), on: s.snowman))
        menu.addItem(.separator())
        menu.addItem(item("اجرا هنگام ورود به سیستم", #selector(toggleLogin),
                          on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item("خروج", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector,
                      key: String = "", on: Bool? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        if let on = on { it.state = on ? .on : .off }
        return it
    }

    @objc private func togglePaused() { Settings.shared.paused.toggle() }
    @objc private func setIntensity(_ sender: NSMenuItem) { Settings.shared.intensity = sender.tag }
    @objc private func toggleWind() { Settings.shared.wind.toggle() }
    @objc private func toggleAccumulate() { Settings.shared.accumulate.toggle() }
    @objc private func toggleSnowman() { Settings.shared.snowman.toggle() }

    @objc private func toggleLogin() {
        // Works only when running from the built .app bundle.
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Barfak: login item change failed: \(error.localizedDescription)")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
