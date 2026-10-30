import SwiftUI

@main
struct MacHelmApp: App {
    @State private var model = AppModel()
    @State private var discovery = Discovery()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("MacHelm", id: "main") {
            RootView()
                .environment(model)
                .environment(discovery)
                .frame(minWidth: 1020, minHeight: 660)
                .task { await model.start() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Mac…") { model.editing = nil; model.showAddSheet = true }.keyboardShortcut("n")
                Button("Command Palette…") { model.showPalette = true }.keyboardShortcut("k")
                Button("Refresh All") { Task { await model.refreshAll() } }.keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: "steeringwheel")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}
