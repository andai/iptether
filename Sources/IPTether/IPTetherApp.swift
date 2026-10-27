import AppKit
import SwiftUI

@main
struct IPTetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }

        Settings {
            SettingsView(model: model)
        }

        Window("Preview Changes", id: PreviewView.windowID) {
            PreviewView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar icon. It exists from launch, so it also opens the Preview window on first
/// run: a menu bar app has no other view that can call `openWindow` before the user clicks.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.iconName)
            .accessibilityLabel("IPTether")
            // `initial: true` covers the request being raised before this view appeared
            .onChange(of: model.setupWindowRequested, initial: true) { _, _ in
                guard model.takeSetupRequest() else { return }
                openWindow(id: PreviewView.windowID)
                bringToFront()
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
        }
    }
}

/// Menu bar apps don't come to the front on their own when they open a window.
@MainActor
func bringToFront() {
    NSApp.activate()
}
