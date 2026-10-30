import SwiftUI

struct FleetView: View {
    @Environment(AppModel.self) private var model
    @Environment(Discovery.self) private var discovery

    private let columns = [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 16)]

    var body: some View {
        ScrollView {
            if model.machines.isEmpty {
                EmptyFleet().frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    ForEach(model.groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: group)
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(model.machines.filter { $0.group == group }) { MachineCard(machine: $0) }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Fleet")
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await model.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { model.editing = nil; model.showAddSheet = true } label: { Label("Add Mac", systemImage: "plus") }
            }
        }
    }

    private var summary: some View {
        let stats = model.machines.compactMap { model.runtime[$0.id]?.stats }
        let avgCPU = stats.isEmpty ? 0 : stats.map(\.cpu).reduce(0, +) / Double(stats.count)
        let low = model.machines.filter { (model.runtime[$0.id]?.stats?.battery ?? 100) < 20 && !(model.runtime[$0.id]?.stats?.onAC ?? false) }.count
        return HStack(spacing: 14) {
            SummaryTile(title: "Online", value: "\(model.onlineCount)/\(model.machines.count)", icon: "wifi", tint: .green)
            SummaryTile(title: "Avg CPU", value: "\(Int(avgCPU))%", icon: "cpu", tint: .blue)
            SummaryTile(title: "Low battery", value: "\(low)", icon: "battery.25", tint: low > 0 ? .orange : .gray)
            SummaryTile(title: "Offline", value: "\(model.machines.count - model.onlineCount)", icon: "wifi.slash", tint: .red)
        }
    }
}

struct SummaryTile: View {
    var title: String, value: String, icon: String, tint: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
                .frame(width: 44, height: 44).background(Circle().fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card(padding: 14)
    }
}

struct MachineCard: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    var body: some View {
        let rt = model.runtime[machine.id]
        let s = rt?.stats
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: machine.icon).font(.title2).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(machine.accent.color.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(machine.name).font(.headline).lineLimit(1)
                    Text(s.map { "\($0.chip) · macOS \($0.os)" } ?? (machine.isLocal ? "This Mac" : machine.host))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                StatusPill(status: rt?.status ?? .unknown)
            }

            if let s, rt?.status == .online {
                VStack(spacing: 9) {
                    metric("CPU", s.cpu / 100, "\(Int(s.cpu))%", .blue)
                    metric("Memory", s.memFraction, "\(s.memUsed.bytesString) / \(s.memTotal.bytesString)", .purple)
                    metric("Disk", s.diskFraction, "\(s.diskFree.diskString) free", .teal)
                }
                HStack {
                    if let b = s.battery {
                        Label("\(b)%\(s.charging ? " ⚡︎" : "")", systemImage: batteryIcon(b, s.onAC)).font(.caption)
                            .foregroundStyle(b < 20 && !s.onAC ? .orange : .secondary)
                    }
                    Label(s.uptime.uptimeString, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if rt?.status == .authRequired {
                Label("SSH key not installed yet — open the machine to set it up.", systemImage: "key.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else if rt?.status == .offline {
                Label(String((rt?.error ?? "Unreachable").prefix(90)), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            HStack(spacing: 6) {
                cardButton("Open", "arrow.up.right.square") { model.selection = .machine(machine.id) }
                cardButton("Screen", "display") { Remote(machine: machine).openScreenSharing() }
                cardButton("Terminal", "terminal") { Remote(machine: machine).openInTerminal() }
                if rt?.status == .offline, !machine.isLocal {
                    cardButton("Wake", "power") { _ = model.wake(machine) }
                }
            }
        }
        .card()
        .onTapGesture(count: 2) { model.selection = .machine(machine.id) }
    }

    private func metric(_ title: String, _ value: Double, _ detail: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            MiniBar(value: value, tint: tint)
        }
    }

    private func cardButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.caption.weight(.medium)).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.small)
    }

    private func batteryIcon(_ pct: Int, _ ac: Bool) -> String {
        switch pct { case ..<15: "battery.0"; case ..<40: "battery.25"; case ..<65: "battery.50"; case ..<90: "battery.75"; default: "battery.100" }
    }
}

struct EmptyFleet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            BrandBadge(size: 110)
            Text("Welcome to MacHelm").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("One place to monitor, control and automate every Mac you own.\nAdd your first machine to get started.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { model.editing = nil; model.showAddSheet = true } label: { Label("Add a Mac", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button { model.addThisMac() } label: { Label("Add This Mac", systemImage: "laptopcomputer") }
                    .buttonStyle(.bordered).controlSize(.large)
            }
            Text("Tip: on each Mac you want to manage, enable System Settings → General → Sharing → Remote Login.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}
