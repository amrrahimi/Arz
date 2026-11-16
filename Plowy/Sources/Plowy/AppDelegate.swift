import AppKit
import ServiceManagement
import SpriteKit

/// SKView that takes the first click even though the app is never active.
final class OverlayView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [NSWindow] = []
    private let snowman = SnowmanController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Plowy") {
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
            let window = NSPanel(contentRect: NSRect(origin: .zero, size: screen.frame.size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true          // the scene turns this off over grabbable things
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                         .fullScreenAuxiliary, .ignoresCycle]
            window.setFrame(screen.frame, display: false)

            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.allowsTransparency = true
            view.ignoresSiblingOrder = true
            view.preferredFramesPerSecond = 60
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            view.presentScene(SnowScene(screen: screen))

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
        let t = L10n.t
        menu.userInterfaceLayoutDirection = L10n.isRightToLeft ? .rightToLeft : .leftToRight

        menu.addItem(item(s.paused ? t("resume") : t("pause"),
                          #selector(togglePaused), key: "p"))
        menu.addItem(.separator())

        let intensity = NSMenuItem(title: t("intensity"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, title) in [t("light"), t("medium"), t("heavy")].enumerated() {
            let it = item(title, #selector(setIntensity(_:)))
            it.tag = i
            it.state = s.intensity == i ? .on : .off
            sub.addItem(it)
        }
        intensity.submenu = sub
        menu.addItem(intensity)

        menu.addItem(item(t("wind"), #selector(toggleWind), on: s.wind))
        menu.addItem(item(t("accumulateMac"), #selector(toggleAccumulate), on: s.accumulate))
        menu.addItem(item(t("iconSnowMac"), #selector(toggleIconSnow), on: s.iconSnow))
        if s.iconSnow && !AXTracker.shared.trusted {
            menu.addItem(item("   " + t("axNeeded"), #selector(requestAccessibility)))
        }
        menu.addItem(item(t("wallpaper"), #selector(toggleWallpaper), on: s.wallpaperSnow))
        menu.addItem(.separator())

        menu.addItem(item(t("lights"), #selector(toggleLights), on: s.lights))
        let style = NSMenuItem(title: t("lightStyle"), action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for (i, title) in [t("styleClassic"), t("styleOnion"), t("stylePastel"), t("styleGlobe")].enumerated() {
            let it = item(title, #selector(setLightStyle(_:)))
            it.tag = i
            it.state = s.lightStyle == i ? .on : .off
            styleMenu.addItem(it)
        }
        style.submenu = styleMenu
        menu.addItem(style)
        menu.addItem(.separator())

        menu.addItem(item(t("plow"), #selector(togglePlow), on: s.plow))
        menu.addItem(item(t("plowNow"), #selector(plowNow)))
        menu.addItem(item(t("cableCar"), #selector(toggleCableCar), on: s.cableCar))
        menu.addItem(item(t("clearCables"), #selector(clearCables)))
        menu.addItem(item(t("snowman"), #selector(toggleSnowman), on: s.snowman))
        menu.addItem(.separator())

        let language = NSMenuItem(title: "🌐 " + t("language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        let system = item(t("systemLanguage"), #selector(setLanguage(_:)), on: s.language.isEmpty)
        system.representedObject = ""
        languageMenu.addItem(system)
        languageMenu.addItem(.separator())
        for (code, name) in L10n.languages {
            let it = item(name, #selector(setLanguage(_:)), on: s.language == code)
            it.representedObject = code
            languageMenu.addItem(it)
        }
        language.submenu = languageMenu
        menu.addItem(language)
        menu.addItem(item(t("loginMac"), #selector(toggleLogin),
                          on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item(t("quit"), #selector(quit), key: "q"))
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        Settings.shared.language = (sender.representedObject as? String) ?? ""
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
    @objc private func toggleLights() { Settings.shared.lights.toggle() }
    @objc private func setLightStyle(_ sender: NSMenuItem) { Settings.shared.lightStyle = sender.tag }
    @objc private func togglePlow() { Settings.shared.plow.toggle() }
    @objc private func plowNow() { NotificationCenter.default.post(name: .plowyPlowNow, object: nil) }
    @objc private func toggleCableCar() { Settings.shared.cableCar.toggle() }
    @objc private func clearCables() { NotificationCenter.default.post(name: .plowyClearCables, object: nil) }
    @objc private func toggleWallpaper() { Settings.shared.wallpaperSnow.toggle() }
    @objc private func requestAccessibility() { AXTracker.shared.requestAccess() }
    @objc private func toggleIconSnow() {
        Settings.shared.iconSnow.toggle()
        if Settings.shared.iconSnow && !AXTracker.shared.trusted { AXTracker.shared.requestAccess() }
    }
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
            NSLog("Plowy: login item change failed: \(error.localizedDescription)")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
