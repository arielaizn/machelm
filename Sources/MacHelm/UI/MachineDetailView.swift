import SwiftUI
import Charts

enum MachineTab: String, CaseIterable, Identifiable {
    case overview = "Overview", terminal = "Terminal", sessions = "Sessions", screen = "Screen"
    case files = "Files", processes = "Processes", apps = "Apps", controls = "Controls", setup = "Connect"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .terminal: "terminal"
        case .sessions: "rectangle.stack"
        case .screen: "display"
        case .files: "folder"
        case .processes: "list.number"
        case .apps: "square.grid.3x3"
        case .controls: "switch.2"
        case .setup: "key.horizontal"
        }
    }
}

struct MachineDetailView: View {
    @Environment(AppModel.self) private var model
    let machine: Machine
    @State private var tab: MachineTab = .overview

    var body: some View {
        let rt = model.runtime[machine.id]
        VStack(spacing: 0) {
            header(rt)
            Divider()
            Group {
                switch tab {
                case .overview: OverviewTab(machine: machine)
                case .terminal: TerminalTab(machine: machine)
                case .sessions: SessionsTab(machine: machine)
                case .screen: ScreenTab(machine: machine)
                case .files: FilesTab(machine: machine)
                case .processes: ProcessesTab(machine: machine)
                case .apps: AppsTab(machine: machine)
                case .controls: ControlsTab(machine: machine)
                case .setup: SetupTab(machine: machine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(machine.name)
        .onAppear { if rt?.status == .authRequired { tab = .setup } }
    }

    private func header(_ rt: Runtime?) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: machine.icon).font(.title).foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(machine.accent.color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name).font(.system(.title2, design: .rounded, weight: .bold))
                    Text(machine.isLocal ? "This Mac" : "\(machine.sshTarget):\(machine.port)").font(.callout).foregroundStyle(.secondary)
                }
                StatusPill(status: rt?.status ?? .unknown)
                Spacer()
                Button { Remote(machine: machine).openScreenSharing() } label: { Label("Share Screen", systemImage: "display") }
                    .buttonStyle(.borderedProminent)
                Button { Remote(machine: machine).openInTerminal() } label: { Label("Terminal.app", systemImage: "terminal") }
                    .buttonStyle(.bordered)
                Button { Task { await model.refresh(machine) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered).help("Refresh")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MachineTab.allCases) { t in
                        Button { tab = t } label: {
                            Label(t.rawValue, systemImage: t.icon).font(.callout.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(tab == t ? Color.accentColor.opacity(0.18) : Color.clear))
                                .foregroundStyle(tab == t ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }
}

// MARK: Overview

struct OverviewTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    var body: some View {
        let rt = model.runtime[machine.id]
        ScrollView {
            if let s = rt?.stats, rt?.status == .online {
                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        HStack(spacing: 26) {
                            RingGauge(value: s.cpu / 100, label: "CPU", detail: "\(s.cores) cores · load \(String(format: "%.2f", s.load))", tint: .blue)
                            RingGauge(value: s.memFraction, label: "Memory", detail: "\(s.memUsed.bytesString) of \(s.memTotal.bytesString)", tint: .purple)
                            RingGauge(value: s.diskFraction, label: "Disk", detail: "\(s.diskFree.diskString) free", tint: .teal)
                            if let b = s.battery {
                                RingGauge(value: Double(b) / 100, label: s.charging ? "Charging" : (s.onAC ? "On AC" : "Battery"),
                                          detail: s.batteryTime.map { "\($0) left" } ?? "—", tint: b < 20 ? .red : .green)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .card(padding: 22)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "System")
                            row("Model", s.model)
                            row("Chip", s.chip)
                            row("macOS", "\(s.os) (\(s.build))")
                            row("Hostname", s.host)
                            row("User", s.user)
                            row("IP address", s.ip.isEmpty ? "—" : s.ip)
                            row("MAC address", s.mac.isEmpty ? "—" : s.mac)
                            row("Uptime", s.uptime.uptimeString)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).card()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Last minutes")
                            history("CPU %", rt?.cpuHistory ?? [], .blue)
                            history("Memory %", rt?.memHistory ?? [], .purple)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).card()
                    }

                    if !machine.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) { SectionTitle(text: "Notes"); Text(machine.notes) }
                            .frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                }
                .padding(24)
            } else {
                ContentUnavailableView {
                    Label(rt?.status.label ?? "Checking…", systemImage: rt?.status == .authRequired ? "key.fill" : "wifi.slash")
                } description: {
                    Text(rt?.error ?? "Waiting for the first reading…")
                } actions: {
                    Button("Try Again") { Task { await model.refresh(machine) } }
                    if rt?.status == .offline, !machine.isLocal { Button("Send Wake-on-LAN") { _ = model.wake(machine) } }
                }
                .padding(.top, 40)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).textSelection(.enabled) }.font(.callout)
    }

    private func history(_ title: String, _ values: [Double], _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart(Array(values.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(tint.opacity(0.18)).interpolationMethod(.monotone)
                LineMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(tint).interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 80)
        }
    }
}

// MARK: Setup / Connect

struct SetupTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine
    @State private var password = ""
    @State private var busy = false
    @State private var output = ""

    private let commands: [(String, String, String)] = [
        ("Enable Remote Login (SSH)", "Required for everything except screen sharing.", "sudo systemsetup -setremotelogin on"),
        ("Enable Screen Sharing / Remote Management", "Lets you view and control the screen.",
         "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -restart -agent -privs -all"),
        ("Allow Wake-on-LAN", "Lets MacHelm wake the Mac from sleep over the network.", "sudo pmset -a womp 1"),
        ("Never sleep on power adapter", "Keeps a headless Mac reachable.", "sudo pmset -c sleep 0 displaysleep 10"),
    ]

    var body: some View {
        let rt = model.runtime[machine.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if machine.isLocal {
                    Label("This is the local Mac — no SSH needed.", systemImage: "checkmark.seal.fill").foregroundStyle(.green).card()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "1 · Passwordless access")
                        HStack {
                            StatusPill(status: rt?.status ?? .unknown)
                            Text(rt?.status == .online ? "MacHelm can reach this Mac with its key." : "Install MacHelm's key once, using this Mac's login password.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        HStack {
                            SecureField("Password for \(machine.user)@\(machine.host)", text: $password)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 320).onSubmit(install)
                            Button(action: install) { Label(busy ? "Installing…" : "Install Key", systemImage: "key.fill") }
                                .buttonStyle(.borderedProminent).disabled(password.isEmpty || busy)
                        }
                        Text("The password is used once to run ssh, is never saved, and only the public key is placed in ~/.ssh/authorized_keys.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !output.isEmpty { OutputBox(text: output, minHeight: 50) }
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "2 · Prepare the target Mac (run once in its Terminal)")
                    ForEach(commands, id: \.0) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.0).font(.callout.weight(.semibold))
                            Text(c.1).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text(c.2).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.2, forType: .string) } label: {
                                    Image(systemName: "doc.on.doc")
                                }.buttonStyle(.borderless).help("Copy")
                            }
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "macOS permissions worth granting on the target")
                    Text("""
                    • Full Disk Access for “sshd-keygen-wrapper” (Privacy & Security) so file browsing reaches protected folders.
                    • Screen Recording for the same entry if remote screenshots come back empty.
                    • Accessibility for it if keystroke / lock-screen actions are ignored.
                    """).font(.callout).foregroundStyle(.secondary)
                }
                .card()
            }
            .padding(24)
        }
    }

    private func install() {
        guard !password.isEmpty else { return }
        busy = true
        Task {
            let r = await KeyManager.install(on: machine, password: password)
            output = r.ok ? "✓ Key installed. Connecting…" : (r.text.isEmpty ? "Failed (exit \(r.status))" : r.text)
            if r.ok { password = ""; await model.refresh(machine) }
            busy = false
        }
    }
}
