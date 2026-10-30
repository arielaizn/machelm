import SwiftUI

// MARK: Menu bar

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BrandBadge(size: 26)
                Text("MacHelm").font(.headline)
                Spacer()
                Text("\(model.onlineCount)/\(model.machines.count) online").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if model.machines.isEmpty { Text("No Macs yet.").font(.callout).foregroundStyle(.secondary) }
            ForEach(model.machines) { m in
                let rt = model.runtime[m.id]
                HStack(spacing: 8) {
                    StatusDot(status: rt?.status ?? .unknown)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(m.name).lineLimit(1)
                        if let s = rt?.stats {
                            Text("CPU \(Int(s.cpu))% · RAM \(Int(s.memFraction * 100))%\(s.battery.map { " · 🔋\($0)%" } ?? "")").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { Remote(machine: m).openScreenSharing() } label: { Image(systemName: "display") }.buttonStyle(.borderless).help("Share screen")
                    Button { Remote(machine: m).openInTerminal() } label: { Image(systemName: "terminal") }.buttonStyle(.borderless).help("Terminal")
                    Button { open(m) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.borderless).help("Open in MacHelm")
                }
            }
            Divider()
            HStack {
                Button("Open MacHelm") { open(nil) }
                Spacer()
                Button("Refresh") { Task { await model.refreshAll() } }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14).frame(width: 340)
    }

    private func open(_ m: Machine?) {
        if let m { model.selection = .machine(m.id) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if NSApplication.shared.windows.first(where: { $0.canBecomeMain }) == nil { openWindow(id: "main") }
        NSApplication.shared.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}

// MARK: Command palette

struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    struct Item: Identifiable {
        let id = UUID()
        var title: String
        var subtitle: String
        var icon: String
        var action: () -> Void
    }

    private var items: [Item] {
        var all: [Item] = [
            .init(title: "Fleet dashboard", subtitle: "Go to", icon: "square.grid.2x2") { model.selection = .fleet },
            .init(title: "Broadcast a command", subtitle: "Go to", icon: "dot.radiowaves.left.and.right") { model.selection = .broadcast },
            .init(title: "Scripts", subtitle: "Go to", icon: "curlybraces") { model.selection = .scripts },
            .init(title: "Automations", subtitle: "Go to", icon: "clock.arrow.2.circlepath") { model.selection = .automations },
            .init(title: "Activity log", subtitle: "Go to", icon: "list.bullet.rectangle") { model.selection = .activity },
            .init(title: "Add a Mac", subtitle: "Action", icon: "plus.circle") { model.editing = nil; model.showAddSheet = true },
            .init(title: "Refresh all machines", subtitle: "Action", icon: "arrow.clockwise") { Task { await model.refreshAll() } },
        ]
        for m in model.machines {
            all.append(.init(title: m.name, subtitle: "Open machine", icon: m.icon) { model.selection = .machine(m.id) })
            all.append(.init(title: "Share screen — \(m.name)", subtitle: "Action", icon: "display") { Remote(machine: m).openScreenSharing() })
            all.append(.init(title: "Terminal — \(m.name)", subtitle: "Action", icon: "terminal") { Remote(machine: m).openInTerminal() })
            if !m.isLocal { all.append(.init(title: "Wake — \(m.name)", subtitle: "Action", icon: "power") { _ = model.wake(m) }) }
        }
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let list = items
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Jump to a Mac or run an action…", text: $query).textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit { if list.indices.contains(index) { list[index].action(); dismiss() } }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(list.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        HStack {
                            Image(systemName: item.icon).frame(width: 24).foregroundStyle(Color.accentColor)
                            Text(item.title)
                            Spacer()
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(i == index ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { item.action(); dismiss() }
                    }
                }.padding(8)
            }
        }
        .frame(width: 560, height: 400)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in index = 0 }
    }
}

// MARK: Settings

struct SettingsView: View {
    @AppStorage("pollInterval") private var pollInterval = 15.0
    @AppStorage("notify") private var notify = true
    @State private var launchAtLogin = AppModel.launchAtLogin
    @State private var publicKey = KeyManager.publicKey
    @State private var copied = false

    var body: some View {
        TabView {
            Form {
                Picker("Refresh every", selection: $pollInterval) {
                    Text("5 seconds").tag(5.0); Text("15 seconds").tag(15.0); Text("30 seconds").tag(30.0); Text("1 minute").tag(60.0)
                }
                Toggle("Notify when a Mac goes offline or comes back", isOn: $notify)
                Toggle("Launch MacHelm at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, v in AppModel.launchAtLogin = v }
            }
            .formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Your MacHelm public key") {
                    Text(publicKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button(copied ? "Copied" : "Copy Public Key") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(publicKey, forType: .string); copied = true
                        }
                        Button("Reveal Key Folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: KeyManager.privateKeyPath)]) }
                    }
                }
                Section("Danger zone") {
                    Button("Generate a New Key…", role: .destructive) { Task { await KeyManager.regenerate(); publicKey = KeyManager.publicKey } }
                    Text("A new key must be installed on every Mac again.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).tabItem { Label("Keys", systemImage: "key") }

            VStack(spacing: 10) {
                BrandBadge(size: 80)
                Text("MacHelm").font(.title.bold())
                Text("Version 1.0.0").foregroundStyle(.secondary)
                Text("Open source under the MIT license.").font(.callout)
                Link("github.com/arielaizn/machelm", destination: URL(string: "https://github.com/arielaizn/machelm")!)
            }
            .padding(30).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
    }
}
