import SwiftUI
import Combine

struct ProcessesTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    struct Proc: Identifiable, Hashable {
        var id: Int { pid }
        var pid: Int
        var cpu: Double
        var mem: Double
        var rss: Double
        var user: String
        var command: String
        var name: String { (command as NSString).lastPathComponent }
    }

    @State private var procs: [Proc] = []
    @State private var selection: Set<Int> = []
    @State private var search = ""
    @State private var auto = true
    @State private var sortByMem = false
    @State private var message = ""

    private let ticker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var visible: [Proc] {
        let f = search.isEmpty ? procs : procs.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.user.localizedCaseInsensitiveContains(search) || String($0.pid) == search }
        return sortByMem ? f.sorted { $0.mem > $1.mem } : f
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by name, user or PID", text: $search).textFieldStyle(.plain)
                Picker("Sort", selection: $sortByMem) { Text("CPU").tag(false); Text("Memory").tag(true) }.pickerStyle(.segmented).frame(width: 150)
                Toggle("Auto", isOn: $auto).toggleStyle(.switch).controlSize(.small)
                Button { kill("TERM") } label: { Label("Quit", systemImage: "xmark.circle") }.disabled(selection.isEmpty)
                Button(role: .destructive) { kill("KILL") } label: { Label("Force Kill", systemImage: "bolt.slash") }.disabled(selection.isEmpty)
            }
            .padding(12).background(.bar)
            Divider()
            Table(visible, selection: $selection) {
                TableColumn("Process") { p in Text(p.name).lineLimit(1) }
                TableColumn("PID") { p in Text(String(p.pid)).monospacedDigit().foregroundStyle(.secondary) }.width(70)
                TableColumn("CPU %") { p in Text(String(format: "%.1f", p.cpu)).monospacedDigit().foregroundStyle(p.cpu > 50 ? .orange : .primary) }.width(70)
                TableColumn("Memory") { p in Text(p.rss.bytesString).monospacedDigit() }.width(90)
                TableColumn("User") { p in Text(p.user).foregroundStyle(.secondary) }.width(110)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary).padding(8) }
        }
        .task { await reload() }
        .onReceive(ticker) { _ in if auto { Task { await reload() } } }
    }

    private func reload() async {
        let r = await model.exec(machine, "ps -Ao pid=,pcpu=,pmem=,rss=,user=,comm= -r | head -n 250", log: false)
        guard r.ok else { message = r.text; return }
        procs = r.stdout.split(separator: "\n").compactMap { line in
            let p = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard p.count == 6, let pid = Int(p[0]) else { return nil }
            return Proc(pid: pid, cpu: Double(p[1]) ?? 0, mem: Double(p[2]) ?? 0, rss: (Double(p[3]) ?? 0) * 1024, user: String(p[4]), command: String(p[5]))
        }
    }

    private func kill(_ sig: String) {
        let ids = selection.map(String.init).joined(separator: " ")
        Task {
            let r = await model.exec(machine, "kill -\(sig) \(ids)", label: "kill -\(sig) \(ids)")
            message = r.ok ? "Signal \(sig) sent to \(selection.count) process(es)." : r.text
            try? await Task.sleep(for: .milliseconds(600))
            await reload()
        }
    }
}
