import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }

        let hosting = NSHostingController(rootView: UsageView(store: store))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient

        // objectWillChange fires before the new values land, so hop to the next run loop turn.
        subscription = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusItem() }

        updateStatusItem()
        store.start()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let healthy = store.claude.error == nil || !store.claude.limits.isEmpty
        button.image = Clawd.image(pixel: 1.1, color: healthy ? Clawd.orange : .secondaryLabelColor)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 0.5]
        if store.highestPercent >= 90 {
            attributes[.foregroundColor] = NSColor.systemRed
        }

        let title = NSMutableAttributedString()
        let claudeText = store.menuBarText
        if !claudeText.isEmpty {
            title.append(NSAttributedString(string: " " + claudeText, attributes: attributes))
        }
        if let codexText = store.codexMenuBarText {
            // Template glyph so it follows the menu bar's light/dark tint.
            let glyph = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex")?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            let attachment = NSTextAttachment()
            attachment.image = glyph
            if let size = glyph?.size {
                attachment.bounds = NSRect(x: 0, y: -1, width: size.width, height: size.height)
            }
            title.append(NSAttributedString(string: "   ", attributes: attributes))
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " " + codexText, attributes: attributes))
        }
        button.attributedTitle = title
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh(ifOlderThan: 20)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
