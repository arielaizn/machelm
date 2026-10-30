import SwiftUI

// MARK: Broadcast

struct BroadcastView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Set<UUID> = []
    @State private var results: [UUID: ShellResult] = [:]
    @State private var running = false
    @State private var command = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Targets")
                    Spacer()
                    Button("All") { selected = Set(model.machines.map(\.id)) }.buttonStyle(.borderless)
                    Button("Online") { selected = Set(model.machines.filter { model.runtime[$0.id]?.status == .online }.map(\.id)) }.buttonStyle(.borderless)
                    Button("None") { selected = [] }.buttonStyle(.borderless)
                }
                List {
                    ForEach(model.groups, id: \.self) { g in
                        Section {
                            ForEach(model.machines.filter { $0.group == g }) { m in
                                Toggle(isOn: Binding(get: { selected.contains(m.id) }, set: { if $0 { selected.insert(m.id) } else { selected.remove(m.id) } })) {
                                    HStack { StatusDot(status: model.runtime[m.id]?.status ?? .unknown); Text(m.name) }
                                }
                            }
                        } header: {
                            Button(g) {
                                let ids = Set(model.machines.filter { $0.group == g }.map(\.id))
                                if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }
            .padding(16).frame(minWidth: 240, idealWidth: 270, maxWidth: 340)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Command")
                    Spacer()
                    Menu {
                        ForEach(model.snippets) { s in Button { command = s.command } label: { Label(s.name, systemImage: s.icon) } }
                    } label: { Label("Snippets", systemImage: "curlybraces") }.menuStyle(.borderlessButton).fixedSize()
                }
                TextEditor(text: $command)
                    .font(.system(.body, design: .monospaced)).frame(height: 110).scrollContentBackground(.hidden)
                    .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.28)))
                HStack {
                    Button(action: run) { Label(running ? "Running…" : "Run on \(selected.count) Mac\(selected.count == 1 ? "" : "s")", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).disabled(running || selected.isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                    Text("⌘↩ to run").font(.caption).foregroundStyle(.tertiary)
                }
                Divider()
                SectionTitle(text: "Results")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.machines.filter { results[$0.id] != nil }) { m in
                            if let r = results[m.id] {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(r.ok ? .green : .red)
                                        Text(m.name).font(.headline)
                                        Spacer()
                                        Text("exit \(r.status)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    OutputBox(text: r.text, minHeight: 36)
                                }
                                .card(padding: 12)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Broadcast")
        .onAppear {
            if !model.broadcastDraft.isEmpty { command = model.broadcastDraft; model.broadcastDraft = "" }
            if selected.isEmpty { selected = Set(model.machines.filter { model.runtime[$0.id]?.status == .online }.map(\.id)) }
        }
    }

    private func run() {
        let targets = model.machines.filter { selected.contains($0.id) }
        results = [:]
        running = true
        let cmd = command
        Task {
            let r = await model.broadcast(cmd, to: targets)
            results = r
            running = false
        }
    }
}

// MARK: Scripts

struct ScriptsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var draft = Snippet(name: "", command: "")

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                Section("Mine") {
                    ForEach(model.customSnippets) { s in Label(s.name, systemImage: s.icon).tag(s.id) }
                        .onDelete { idx in model.customSnippets.remove(atOffsets: idx); model.save() }
                }
                Section("Built-in") {
                    ForEach(Snippet.builtins) { s in Label(s.name, systemImage: s.icon).tag(s.id) }
                }
            }
            .frame(minWidth: 240, idealWidth: 270, maxWidth: 340)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder).font(.title3).disabled(draft.builtin)
                TextEditor(text: $draft.command).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.28)))
                    .disabled(draft.builtin)
                HStack {
                    Button { model.broadcastDraft = draft.command; model.selection = .broadcast } label: { Label("Run on machines…", systemImage: "dot.radiowaves.left.and.right") }
                        .buttonStyle(.borderedProminent).disabled(draft.command.isEmpty)
                    if draft.builtin {
                        Button("Duplicate to Mine") {
                            var c = draft; c.id = UUID(); c.builtin = false; model.customSnippets.append(c); model.save(); selection = c.id
                        }
                    } else {
                        Button("Save") {
                            if let i = model.customSnippets.firstIndex(where: { $0.id == draft.id }) { model.customSnippets[i] = draft; model.save() }
                        }.disabled(!model.customSnippets.contains(where: { $0.id == draft.id }))
                    }
                    Spacer()
                }
            }
            .padding(20)
        }
        .navigationTitle("Scripts")
        .toolbar {
            Button { let s = Snippet(name: "New script", command: "echo hello from $(hostname)"); model.customSnippets.append(s); model.save(); selection = s.id } label: { Label("New Script", systemImage: "plus") }
        }
        .onChange(of: selection) { _, id in
            if let s = model.snippets.first(where: { $0.id == id }) { draft = s }
        }
    }
}

// MARK: Automations

struct AutomationsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Automation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Automations run while MacHelm is open (it can live in the menu bar). Each one executes a script on a set of Macs at a fixed interval and alerts you if anything fails.")
                    .font(.callout).foregroundStyle(.secondary)
                if model.automations.isEmpty {
                    ContentUnavailableView("No automations yet", systemImage: "clock.arrow.2.circlepath",
                                           description: Text("Try “every 30 minutes, check disk space on all Macs”."))
                }
                ForEach(model.automations) { a in
                    HStack(spacing: 14) {
                        Toggle("", isOn: Binding(get: { a.enabled }, set: { v in
                            if let i = model.automations.firstIndex(where: { $0.id == a.id }) { model.automations[i].enabled = v; model.save() }
                        })).labelsHidden().toggleStyle(.switch)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.headline)
                            Text("Every \(a.intervalMinutes) min · \(a.group.map { "group “\($0)”" } ?? "\(a.machineIDs.count) Mac(s)")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(a.command).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(a.lastSummary ?? "Never ran").font(.caption)
                            if let d = a.lastRun { Text(d.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Button("Run Now") { Task { await model.run(automation: a) } }
                        Button { editing = a } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                        Button(role: .destructive) { model.automations.removeAll { $0.id == a.id }; model.save() } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    .card()
                }
            }
            .padding(24)
        }
        .navigationTitle("Automations")
        .toolbar {
            Button { editing = Automation(name: "", command: "") } label: { Label("New Automation", systemImage: "plus") }
        }
        .sheet(item: $editing) { AutomationEditor(automation: $0) }
    }
}

struct AutomationEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var automation: Automation
    @State private var useGroup = false

    var body: some View {
        Form {
            Section("Automation") {
                TextField("Name", text: $automation.name)
                Picker("Snippet", selection: Binding(get: { UUID() }, set: { id in
                    if let s = model.snippets.first(where: { $0.id == id }) { automation.command = s.command; if automation.name.isEmpty { automation.name = s.name } }
                })) {
                    Text("Load from snippet…").tag(UUID())
                    ForEach(model.snippets) { Text($0.name).tag($0.id) }
                }
                TextEditor(text: $automation.command).font(.system(.callout, design: .monospaced)).frame(height: 90)
                Stepper("Every \(automation.intervalMinutes) minutes", value: $automation.intervalMinutes, in: 1...1440, step: 5)
                Toggle("Notify me when it fails", isOn: $automation.notifyOnFailure)
            }
            Section("Targets") {
                Toggle("Target a whole group", isOn: $useGroup)
                if useGroup {
                    Picker("Group", selection: Binding(get: { automation.group ?? model.groups.first ?? "" }, set: { automation.group = $0 })) {
                        ForEach(model.groups, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    ForEach(model.machines) { m in
                        Toggle(m.name, isOn: Binding(get: { automation.machineIDs.contains(m.id) }, set: { on in
                            if on { automation.machineIDs.append(m.id) } else { automation.machineIDs.removeAll { $0 == m.id } }
                        }))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear { useGroup = automation.group != nil }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if !useGroup { automation.group = nil }
                    if let i = model.automations.firstIndex(where: { $0.id == automation.id }) { model.automations[i] = automation } else { model.automations.append(automation) }
                    model.save(); dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(automation.name.isEmpty || automation.command.isEmpty)
            }.padding(14).background(.bar)
        }
    }
}

// MARK: Activity

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var expanded: Set<UUID> = []

    var body: some View {
        let rows = filter.isEmpty ? model.activity : model.activity.filter {
            $0.machine.localizedCaseInsensitiveContains(filter) || $0.command.localizedCaseInsensitiveContains(filter) || $0.output.localizedCaseInsensitiveContains(filter)
        }
        List(rows) { e in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: e.status == 0 ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(e.status == 0 ? .green : .red)
                    Text(e.machine).font(.headline)
                    Text(e.command.replacingOccurrences(of: "\n", with: " ")).font(.system(.callout, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Text(e.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.tertiary)
                }
                if expanded.contains(e.id), !e.output.isEmpty { OutputBox(text: e.output, minHeight: 40) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if expanded.contains(e.id) { expanded.remove(e.id) } else { expanded.insert(e.id) } }
        }
        .searchable(text: $filter, prompt: "Search activity")
        .navigationTitle("Activity")
        .toolbar { Button("Clear") { model.activity = []; model.save() } }
        .overlay { if model.activity.isEmpty { ContentUnavailableView("Nothing yet", systemImage: "list.bullet.rectangle", description: Text("Every command MacHelm runs on your Macs is logged here.")) } }
    }
}
