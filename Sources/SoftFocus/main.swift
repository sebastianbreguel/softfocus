import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory = menu-bar app with no Dock icon and no main window.
app.setActivationPolicy(.accessory)
app.run()
