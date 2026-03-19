import AppKit

@MainActor
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        activateAppAndBringWindowsForward()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bringWindowsForward()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        activateAppAndBringWindowsForward()
        return true
    }

    private func activateAppAndBringWindowsForward() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await Task.yield()
            bringWindowsForward()
        }
    }

    private func bringWindowsForward() {
        for window in NSApplication.shared.windows.reversed() {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
