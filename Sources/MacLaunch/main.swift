import AppKit

let app = NSApplication.shared
// A second copy should reveal the running launcher instead of competing for its hotkey.
if let identifier = Bundle.main.bundleIdentifier,
   let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    running.activate(options: [.activateAllWindows])
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
