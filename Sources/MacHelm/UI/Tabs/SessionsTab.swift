import SwiftUI
import Combine

/// Long-running background jobs that survive closing MacHelm: each one is a detached process on the
/// target Mac with its own log, managed through ~/.machelm/jobs.
struct SessionsTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    struct Job: Identifiable, Hashable {
        var id: String
        var name: String
        var alive: Bool
        var exit: String
        var started: Date?
    }

    @State private var jobs: [Job] = []
    @State private var selected: String?
    @State private var log = ""
    @State private var name = ""
    @State private var command = ""
    @State private var message = ""
    @State private var follow = true

    private let ticker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "New background session")
                TextField("Name (e.g. Backup, Render)", text: $name).textFieldStyle(.roundedBorder)
                TextEditor(text: $command)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 90).scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                Button(action: start) { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                Divider()
                HStack {
                    SectionTitle(text: "Sessions")
                    Spacer()
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                }
                List(jobs, selection: $selected) { j in
                    HStack {
                        Image(systemName: j.alive ? "circle.fill" : (j.exit == "0" ? "checkmark.circle.fill" : "xmark.circle.fill"))
                            .foregroundStyle(j.alive ? .green : (j.exit == "0" ? .secondary : .red))
                        VStack(alignment: .leading) {
                            Text(j.name).lineLimit(1)
                            Text(j.alive ? "running" : "exit \(j.exit.isEmpty ? "?" : j.exit)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tag(j.id)
                }
                .listStyle(.inset)
            }
            .padding(16)
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(text: "Live log")
                    Spacer()
                    Toggle("Follow", isOn: $follow).toggleStyle(.switch).controlSize(.small)
                    if let j = jobs.first(where: { $0.id == selected }) {
                        if j.alive { Button("Stop", role: .destructive) { stop(j) } }
                        Button("Remove") { remove(j) }
                    }
                }
                OutputBox(text: log, minHeight: 300).frame(maxHeight: .infinity)
            }
            .padding(16)
        }
        .task { await reload() }
        .onReceive(ticker) { _ in Task { await reload() } }
        .onChange(of: selected) { _, _ in Task { await loadLog() } }
    }

    private func reload() async {
        let script = #"""
        for d in "$HOME"/.machelm/jobs/*/; do
          [ -d "$d" ] || continue
          id=$(basename "$d"); pid=$(cat "$d/pid" 2>/dev/null); alive=0
          kill -0 "$pid" 2>/dev/null && alive=1
          printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$(cat "$d/name" 2>/dev/null)" "$alive" "$(cat "$d/exit" 2>/dev/null)" "$(cat "$d/started" 2>/dev/null)"
        done
        """#
        let r = await model.exec(machine, script, log: false)
        guard r.ok else { return }
        jobs = r.stdout.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 5 else { return nil }
            return Job(id: p[0], name: p[1], alive: p[2] == "1", exit: p[3], started: TimeInterval(p[4]).map { Date(timeIntervalSince1970: $0) })
        }.sorted { ($0.started ?? .distantPast) > ($1.started ?? .distantPast) }
        if follow { await loadLog() }
    }

    private func loadLog() async {
        guard let id = selected else { log = ""; return }
        let r = await model.exec(machine, "tail -n 400 \"$HOME/.machelm/jobs/\(id)/log\" 2>&1", log: false)
        log = r.text
    }

    private func start() {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? String(cmd.prefix(28)) : name
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let b64 = Data(cmd.utf8).base64EncodedString()
        let script = """
        d="$HOME/.machelm/jobs/\(id)"; mkdir -p "$d"
        printf '%s' \(shq(title)) > "$d/name"; date +%s > "$d/started"
        printf '%s' \(shq(b64)) | base64 -D > "$d/cmd.sh" 2>/dev/null || printf '%s' \(shq(b64)) | base64 -d > "$d/cmd.sh"
        ( /bin/zsh -l "$d/cmd.sh"; echo $? > "$d/exit" ) > "$d/log" 2>&1 < /dev/null &
        echo $! > "$d/pid"
        echo started
        """
        Task {
            let r = await model.exec(machine, script, label: "session: \(cmd)")
            message = r.ok ? "Started “\(title)”." : r.text
            if r.ok { name = ""; command = ""; selected = id }
            await reload()
        }
    }

    private func stop(_ j: Job) {
        Task {
            _ = await model.exec(machine, "d=\"$HOME/.machelm/jobs/\(j.id)\"; pid=$(cat \"$d/pid\"); pkill -P $pid 2>/dev/null; kill $pid 2>/dev/null; echo 143 > \"$d/exit\"", label: "stop session \(j.name)")
            await reload()
        }
    }

    private func remove(_ j: Job) {
        Task {
            _ = await model.exec(machine, "rm -rf \"$HOME/.machelm/jobs/\(j.id)\"", log: false)
            if selected == j.id { selected = nil; log = "" }
            await reload()
        }
    }
}
