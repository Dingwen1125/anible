import AppKit

private let app = NSApplication.shared
private let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: PetManagerWindowController?
    private var petWindowController: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        petWindowController = PetWindowController { [weak self] in
            self?.showManagerWindow()
        }
        petWindowController?.show()

        mainWindowController = PetManagerWindowController { [weak self] profile in
            self?.petWindowController?.useProfile(profile)
        }
        showManagerWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showManagerWindow() {
        NSApp.setActivationPolicy(.regular)
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
