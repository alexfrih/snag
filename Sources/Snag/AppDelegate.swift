import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let snagPopoverDidOpen = Notification.Name("snagPopoverDidOpen")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let manager = DownloadManager()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            applyIcon(activeCount: 0)
        }

        let hosting = NSHostingController(
            rootView: ContentView(manager: manager, onQuit: { [weak self] in self?.quit() })
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        manager.$activeCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in self?.applyIcon(activeCount: count) }
            .store(in: &cancellables)
    }

    private func applyIcon(activeCount: Int) {
        guard let button = statusItem.button else { return }
        let symbol = activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Snag")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.title = activeCount > 0 ? " \(activeCount)" : ""
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .snagPopoverDidOpen, object: nil)
        }
    }

    private func quit() { NSApp.terminate(nil) }
}
