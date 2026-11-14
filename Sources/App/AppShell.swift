// A NORMAL MAC APP (v73, request 86, Marko 14.11.2026: "please build Connection Keeper as a normal app, so I can start it
// from the dock. I can minimize it. I can move it. It has its settings in the menu bar, etc"), and request 87: open =
// Frankfurt, quit = the Mac as before (Session.swift).
//   - a Dock icon and ⌘-Tab (activation policy .regular); a click on the Dock icon brings the window back;
//   - the stripe is a titled window: the system's own traffic lights, minimize to the Dock, moved by its title bar,
//     resized by its edges (the width; the content scales as with the grip); its place remembered;
//   - the main menu: Connection Keeper (About, Settings… ⌘,, Check for Updates…, Hide, Quit ⌘Q), View, Window, Help;
//   - Quit closes the session cleanly (Session.close) and only then ends; an update keeps the session for its successor.
import AppKit

enum WindowPrefs {
    static let atLoginKey = "openWindowAtLogin"
    static var openAtLogin: Bool {
        get { UserDefaults.standard.object(forKey: atLoginKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: atLoginKey) }
    }
}

// A panel that can be the main window (a plain NSPanel cannot), so the Window menu and ⌘` treat it as the app's window.
final class StripeWindow: NSPanel {
    override var canBecomeMain: Bool { true }
    override var canBecomeKey: Bool { true }
}

final class AppShell: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppShell()
    var updating = false                 // set by the updater: the quit keeps the session (its successor takes it over)
    var closing = false
    var offDone = false                  // OFF has cleaned up already: quit at once

    func install(on app: NSApplication) {
        app.delegate = self
        app.mainMenu = buildMenu()
        stripe.panel.delegate = self
    }

    // MARK: lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func showWindow() {
        MenuBarPrefs.stripeHidden = false
        if stripe.panel.isMiniaturized { stripe.panel.deminiaturize(nil) }
        stripe.panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if offDone { return .terminateNow }
        if updating || CommandLine.arguments.contains("--selftest") {
            if updating { Session.markUpdating(); appendLog("\(logStamp()) QUIT for an update: the session stays for the new copy") }
            return .terminateNow
        }
        if closing { return .terminateLater }
        closing = true
        appendLog("\(logStamp()) QUIT: back to the Mac's normal connection")
        DispatchQueue.global().async {
            Session.close { appendLog("\(logStamp()) \($0)") }
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    // MARK: the window

    // The red button hides the window (the app and the session keep running; the Dock icon or the menu bar icon brings
    // it back). Quit is ⌘Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MenuBarPrefs.stripeHidden = true
        sender.orderOut(nil)
        return false
    }

    // v81 (request 89): down in the Dock it stays down; only his click (the Dock icon, the window's Dock tile, the menu bar
    // icon, ⌘-Tab + reopen) brings it back, and then the size it waited for is applied.
    func windowDidMiniaturize(_ notification: Notification) {
        appendLog("\(logStamp()) WINDOW down in the Dock")
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        let how = NSApp.currentEvent.map { "event type \($0.type.rawValue)" } ?? "no event"
        appendLog("\(logStamp()) WINDOW back from the Dock (\(how))")
        stripe.fitWaiting = false
        stripe.fit()
    }

    // An edge drag changes the width; the height follows the content (the stripe's own fit).
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, 320), height: sender.frame.height)
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        stripe.resize(toWidth: stripe.panel.contentRect(forFrameRect: stripe.panel.frame).width)
        StripePlace.save(stripe.panel)
    }
    func windowDidMove(_ notification: Notification) { StripePlace.save(stripe.panel) }

    // MARK: the menu

    func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil, mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        return i
    }

    func buildMenu() -> NSMenu {
        let main = NSMenu()
        let name = "Connection Keeper"

        let appMenu = NSMenu(title: name)
        appMenu.addItem(item("About \(name)", #selector(about), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(settings), ",", target: self))
        appMenu.addItem(item("Check for Updates…", #selector(checkUpdates), target: self))
        let atLogin = item("Open Window at Login", #selector(toggleAtLogin(_:)), target: self)
        atLogin.state = WindowPrefs.openAtLogin ? .on : .off
        appMenu.addItem(atLogin)
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", mods: [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(name) (back to the normal connection)", #selector(NSApplication.terminate(_:)), "q"))
        appMenu.addItem(item("OFF: Stop Everything and Quit", #selector(off), target: self))
        add(appMenu, to: main)

        let view = NSMenu(title: "View")
        view.addItem(item("All Lines", #selector(Stripe.pickTabAll), "1", target: stripe))
        view.addItem(item("Lines in Use", #selector(Stripe.pickTabUse), "2", target: stripe))
        view.addItem(item("LAN Only", #selector(Stripe.pickLanFilter), "3", target: stripe))
        view.addItem(item("Wi-Fi Only", #selector(Stripe.pickWifiFilter), "4", target: stripe))
        view.addItem(.separator())
        view.addItem(item("Frankfurt (through the relay)", #selector(Stripe.pickFrankfurt), "f", target: stripe, mods: [.command, .shift]))
        view.addItem(item("Croatia (straight)", #selector(Stripe.pickCroatia), "c", target: stripe, mods: [.command, .shift]))
        view.addItem(.separator())
        view.addItem(item("Speed Test", #selector(Stripe.testSpeedPressed), "t", target: stripe))
        view.addItem(item("Health Test", #selector(Stripe.testHealthPressed), "", target: stripe))
        view.addItem(item("Always on Top", #selector(Stripe.toggleTop), "", target: stripe))
        add(view, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(item("Show the Stripe", #selector(show), "0", target: self))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        add(window, to: main)
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(item("\(name) Help", #selector(Stripe.helpPressed), "?", target: stripe))
        add(help, to: main)
        NSApp.helpMenu = help
        return main
    }

    func add(_ m: NSMenu, to main: NSMenu) {
        let holder = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
        holder.submenu = m
        main.addItem(holder)
    }

    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: appName, .applicationVersion: "v\(CKVersion)", .version: ""])
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func settings() { stripe.openSettings(); NSApp.activate(ignoringOtherApps: true) }
    @objc func checkUpdates() { Updater.checkAtStart(delay: 0, manual: true) }
    @objc func show() { showWindow() }
    @objc func off() { stripe.switchOff() }
    @objc func toggleAtLogin(_ i: NSMenuItem) {
        WindowPrefs.openAtLogin.toggle()
        i.state = WindowPrefs.openAtLogin ? .on : .off
    }
}
