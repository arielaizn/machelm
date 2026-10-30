import SwiftUI

struct MachineEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(Discovery.self) private var discovery
    @Environment(\.dismiss) private var dismiss

    let existing: Machine?
    @State private var m = Machine(name: "", host: "", user: NSUserName())
    @State private var password = ""
    @State private var busy = false
    @State private var note = ""

    var body: some View {
        HStack(spacing: 0) {
            Form {
                Section(existing == nil ? "Add a Mac" : "Edit Mac") {
                    TextField("Name", text: $m.name, prompt: Text("Studio MacBook"))
                    TextField("Host or IP", text: $m.host, prompt: Text("192.168.1.20 or studio.local")).disabled(m.isLocal)
                    TextField("User", text: $m.user)
                    TextField("SSH port", value: $m.port, format: .number.grouping(.never))
                    TextField("Group", text: $m.group)
                    TextField("MAC address (for Wake-on-LAN)", text: $m.macAddress, prompt: Text("auto-detected"))
                }
                Section("Appearance") {
                    Picker("Icon", selection: $m.icon) {
                        ForEach(Machine.icons, id: \.self) { Label($0, systemImage: $0).labelStyle(.iconOnly).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Color", selection: $m.accent) {
                        ForEach(Accent.allCases) { a in Text(a.rawValue.capitalized).tag(a) }
                    }
                    TextField("Notes", text: $m.notes, axis: .vertical).lineLimit(2...4)
                }
                if existing == nil && !m.isLocal {
                    Section("Passwordless access (optional now)") {
                        SecureField("Account password to install MacHelm's key", text: $password)
                        Text("Used once, never stored. You can also do this later from the Connect tab.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.orange) }
            }
            .formStyle(.grouped)
            .frame(minWidth: 420)

            if existing == nil {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: "On your network")
                        Spacer()
                        if discovery.scanning { ProgressView().controlSize(.small) }
                        Button { discovery.start() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                    }
                    if discovery.found.isEmpty {
                        Text(discovery.scanning ? "Looking for Macs with Remote Login enabled…" : "Nothing found. Enable Remote Login on the other Mac, or type its address.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    List(discovery.found) { f in
                        HStack {
                            Image(systemName: "laptopcomputer")
                            VStack(alignment: .leading) { Text(f.name); Text(f.host).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Use") { m.name = f.name; m.host = f.host; m.port = f.port }.controlSize(.small)
                        }
                    }
                    .listStyle(.inset)
                    Button { model.addThisMac(); dismiss() } label: { Label("Add This Mac instead", systemImage: "laptopcomputer") }
                        .buttonStyle(.bordered).disabled(model.machines.contains(where: \.isLocal))
                }
                .padding(16).frame(width: 260)
            }
        }
        .frame(minHeight: 520)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(busy ? "Saving…" : "Save", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(m.name.isEmpty || m.user.isEmpty || (m.host.isEmpty && !m.isLocal) || busy)
            }
            .padding(14).background(.bar)
        }
        .onAppear {
            if let e = existing { m = e } else { discovery.start() }
        }
        .onDisappear { discovery.stop() }
    }

    private func save() {
        busy = true
        let machine = m
        Task {
            if existing == nil, !machine.isLocal, !password.isEmpty {
                let r = await KeyManager.install(on: machine, password: password)
                if !r.ok { note = "Saved, but key install failed: \(String(r.text.prefix(160)))" }
            }
            model.upsert(machine)
            if existing == nil { model.selection = .machine(machine.id) }
            busy = false
            dismiss()
        }
    }
}
