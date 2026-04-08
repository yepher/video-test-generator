//
//  AppDelegate.swift
//  TestCamera
//
//  Main application delegate. Creates the window programmatically.
//  Checks if the app is running from /Applications and offers to copy itself there.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the menu bar (required for programmatic apps without storyboards)
        setupMenuBar()

        // Check if running from /Applications
        checkApplicationsLocation()

        let viewController = ViewController()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window?.title = "Test Camera"
        window?.contentViewController = viewController
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // Bring the app to the foreground — required when there's no storyboard
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Test Camera", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Test Camera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Edit menu (for copy/paste in text fields)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func checkApplicationsLocation() {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasPrefix("/Applications/") {
            return // Already running from /Applications
        }

        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "Virtual camera extensions require the app to run from the /Applications folder.\n\nWould you like to copy TestCamera to /Applications now?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Copy to Applications")
        alert.addButton(withTitle: "Continue Anyway")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            copyToApplications()
        } else {
            let infoAlert = NSAlert()
            infoAlert.messageText = "Running Outside /Applications"
            infoAlert.informativeText = "The camera extension cannot be activated from this location. To use the virtual camera, please move TestCamera.app to /Applications and relaunch."
            infoAlert.alertStyle = .informational
            infoAlert.addButton(withTitle: "OK")
            infoAlert.runModal()
        }
    }

    private func copyToApplications() {
        let sourcePath = Bundle.main.bundlePath
        let destPath = "/Applications/TestCamera.app"

        let fileManager = FileManager.default

        do {
            // Remove existing copy if present
            if fileManager.fileExists(atPath: destPath) {
                try fileManager.removeItem(atPath: destPath)
            }
            try fileManager.copyItem(atPath: sourcePath, toPath: destPath)

            let alert = NSAlert()
            alert.messageText = "Copied Successfully"
            alert.informativeText = "TestCamera has been copied to /Applications.\n\nThe app will now quit. Please relaunch from /Applications/TestCamera.app."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Quit")
            alert.runModal()

            // Launch the copy and quit this instance
            NSWorkspace.shared.open(URL(fileURLWithPath: destPath))
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Copy Failed"
            alert.informativeText = "Could not copy to /Applications: \(error.localizedDescription)\n\nPlease manually drag TestCamera.app to /Applications."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
