import SwiftUI

struct TerminalTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    struct Entry: Identifiable {
        let id = UUID()
        var cwd: String
        var command: String
        var raw = ""
        var done = false
        var status: Int32 = 0
    }

    private static let marker = "__MH_CWD__"

    @State private var entries: [Entry] = []
    @State private var input = ""
    @State private var cwd = "~"
    @State private var running: LiveProcess?
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if entries.isEmpty {
                            Text("Run commands on \(machine.name). The working directory persists between commands. Interactive programs (vim, top) belong in Terminal.app — use the button above or a tmux session.")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        ForEach(entries) { e in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("\(machine.user)@\(machine.name) \(e.cwd) %").foregroundStyle(.green)
                                    Text(e.command).foregroundStyle(.primary)
                                    if e.done, e.status != 0 { Text("exit \(e.status)").foregroundStyle(.red) }
                                    if !e.done { ProgressView().controlSize(.mini) }
                                }
                                let out = display(e.raw)
                                if !out.isEmpty { Text(out).foregroundStyle(.primary.opacity(0.9)).textSelection(.enabled) }
                            }
                            .id(e.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .background(Color.black.opacity(0.30))
                .onChange(of: entries.last?.raw) { _, _ in proxy.scrollTo("bottom") }
                .onChange(of: entries.count) { _, _ in proxy.scrollTo("bottom") }
            }
            Divider()
            HStack(spacing: 10) {
                Text("\(cwd) %").font(.system(.callout, design: .monospaced)).foregroundStyle(.green)
                TextField("command", text: $input)
                    .textFieldStyle(.plain).font(.system(.callout, design: .monospaced))
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.upArrow) { step(-1); return .handled }
                    .onKeyPress(.downArrow) { step(1); return .handled }
                    .disabled(running != nil)
                if running != nil {
                    Button { running?.terminate() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.bordered).tint(.red)
                }
                Button { entries.removeAll() } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Clear")
                if !machine.isLocal {
                    Button { Remote(machine: machine).openInTerminal(remoteCommand: "tmux new -A -s machelm") } label: {
                        Label("tmux", systemImage: "rectangle.split.2x1")
                    }.buttonStyle(.bordered).help("Open a persistent tmux session in Terminal.app")
                }
            }
            .padding(12)
            .background(.bar)
        }
        .onAppear { focused = true }
    }

    private func display(_ raw: String) -> String {
        var s = raw
        if let r = s.range(of: "\n" + Self.marker) ?? s.range(of: Self.marker) { s = String(s[..<r.lowerBound]) }
        return s.trimmingCharacters(in: .newlines)
    }

    private func step(_ delta: Int) {
        guard !history.isEmpty else { return }
        let next = (historyIndex ?? history.count) + delta
        if next >= history.count { historyIndex = nil; input = ""; return }
        historyIndex = max(0, next)
        input = history[historyIndex!]
    }

    private func submit() {
        let cmd = input.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty, running == nil else { return }
        input = ""
        history.append(cmd)
        historyIndex = nil

        let entry = Entry(cwd: cwd, command: cmd)
        entries.append(entry)
        let id = entry.id
        let dir = cwd == "~" ? "\"$HOME\"" : (cwd.hasPrefix("~/") ? "\"$HOME\"/" + shq(String(cwd.dropFirst(2))) : shq(cwd))
        let script = "cd \(dir) 2>/dev/null\n\(cmd)\n__mh_rc=$?\nprintf '\\n\(Self.marker)%s\\n' \"$PWD\"\nexit $__mh_rc\n"

        running = Remote(machine: machine).stream(script, onOutput: { chunk in
            Task { @MainActor in
                if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].raw += chunk }
            }
        }, onExit: { status in
            Task { @MainActor in
                if let i = entries.firstIndex(where: { $0.id == id }) {
                    entries[i].done = true
                    entries[i].status = status
                    if let r = entries[i].raw.range(of: Self.marker) {
                        let path = entries[i].raw[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !path.isEmpty { cwd = path.replacingOccurrences(of: "/Users/\(machine.user)", with: "~") }
                    }
                    model.record(machine, cmd, ShellResult(data: Data(display(entries[i].raw).utf8), stderr: "", status: status))
                }
                running = nil
                focused = true
            }
        })
    }
}
