import AppKit

// `Barfak --dump-art <dir>` writes a preview sheet of the artwork and exits.
if let i = CommandLine.arguments.firstIndex(of: "--dump-art"), i + 1 < CommandLine.arguments.count {
    Art.dump(to: CommandLine.arguments[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
