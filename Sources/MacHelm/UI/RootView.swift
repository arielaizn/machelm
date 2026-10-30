import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 320)
        } detail: {
            switch model.selection ?? .fleet {
            case .fleet: FleetView()
            case .broadcast: BroadcastView()
            case .scripts: ScriptsView()
            case .automations: AutomationsView()
            case .activity: ActivityView()
            case .machine(let id):
                if let m = model.machine(id) { MachineDetailView(machine: m).id(m.id) } else { FleetView() }
            }
        }
        .sheet(isPresented: $model.showAddSheet) { MachineEditor(existing: model.editing) }
        .sheet(isPresented: $model.showPalette) { CommandPalette() }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            HStack(spacing: 10) {
                BrandBadge(size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacHelm").font(.system(.headline, design: .rounded, weight: .bold))
                    Text("\(model.onlineCount) of \(model.machines.count) online").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)

            Section("Control Center") {
                Label("Fleet", systemImage: "square.grid.2x2").tag(SidebarItem.fleet)
                Label("Broadcast", systemImage: "dot.radiowaves.left.and.right").tag(SidebarItem.broadcast)
                Label("Scripts", systemImage: "curlybraces").tag(SidebarItem.scripts)
                Label("Automations", systemImage: "clock.arrow.2.circlepath").tag(SidebarItem.automations)
                Label("Activity", systemImage: "list.bullet.rectangle").tag(SidebarItem.activity)
            }

            ForEach(model.groups, id: \.self) { group in
                Section(group) {
                    ForEach(model.machines.filter { $0.group == group }) { m in
                        MachineRow(machine: m).tag(SidebarItem.machine(m.id))
                            .contextMenu {
                                Button("Edit…") { model.editing = m; model.showAddSheet = true }
                                Button("Share Screen") { Remote(machine: m).openScreenSharing() }
                                Button("Open Terminal") { Remote(machine: m).openInTerminal() }
                                Divider()
                                Button("Remove", role: .destructive) { model.delete(m) }
                            }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { model.editing = nil; model.showAddSheet = true } label: { Label("Add Mac", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                Spacer()
                Button { model.showPalette = true } label: { Image(systemName: "command") }
                    .buttonStyle(.borderless).help("Command palette (⌘K)")
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless)
            }
            .padding(12)
            .background(.bar)
        }
    }
}

struct MachineRow: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    var body: some View {
        let rt = model.runtime[machine.id]
        HStack(spacing: 10) {
            Image(systemName: machine.icon).foregroundStyle(machine.accent.color).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name).lineLimit(1)
                Text(machine.isLocal ? "This Mac" : machine.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let b = rt?.stats?.battery {
                Text("\(b)%").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            StatusDot(status: rt?.status ?? .unknown)
        }
    }
}
