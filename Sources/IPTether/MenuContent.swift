import AppKit
import SwiftUI

/// The menu under the menu bar icon.
struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.statusLine)
        if let warning = model.warning {
            Text("⚠︎ \(warning)")
        }

        Divider()

        if model.needsSetup {
            Button("Set Up IPTether…") { showPreview() }
            Divider()
        }

        Button("Sync Now") { model.syncNow() }
            .keyboardShortcut("s")
            .disabled(model.isRunning)
        Button("Full Sweep") { model.fullSweep() }
            .keyboardShortcut("f")
            .disabled(model.isRunning)
        Button("Preview Changes…") { showPreview() }
            .keyboardShortcut("p")

        Divider()

        Toggle("Automatic Updates", isOn: Binding(
            get: { model.config.schedule.automatic },
            set: { model.setAutomatic($0) }
        ))

        Divider()

        Button("Remove My IP…") { confirmRemove() }
            .disabled(model.isRunning)
        Button("Open Log") { model.openLog() }
            .keyboardShortcut("l")
        Button("Settings…") {
            openSettings()
            bringToFront()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit IPTether") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showPreview() {
        openWindow(id: PreviewView.windowID)
        bringToFront()
    }

    private func confirmRemove() {
        bringToFront()
        let alert = NSAlert()
        alert.messageText = "Remove your IP from all firewalls?"
        alert.informativeText = "IPTether deletes only the rules it added for this Mac. Other rules aren't touched. Automatic updates turn off so the IP isn't added back."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.removeMyIP()
        }
    }
}
