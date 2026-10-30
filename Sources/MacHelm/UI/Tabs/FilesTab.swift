import SwiftUI
import UniformTypeIdentifiers

struct FilesTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    struct Item: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var isDir: Bool
        var size: Int64
        var modified: Date
        var perms: String
    }

    @State private var path = "~"
    @State private var resolved = ""
    @State private var items: [Item] = []
    @State private var selection: Set<String> = []
    @State private var status = ""
    @State private var loading = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var confirmDelete = false
    @State private var preview: (String, String)?
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { go(parent(resolved)) } label: { Image(systemName: "chevron.up") }.disabled(resolved == "/")
                Button { go("~") } label: { Image(systemName: "house") }
                TextField("Path", text: $path).textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
                    .onSubmit { go(path) }
                Button { Task { await load(path) } } label: { Image(systemName: "arrow.clockwise") }
                Divider().frame(height: 20)
                Button { newFolderName = ""; showNewFolder = true } label: { Label("Folder", systemImage: "folder.badge.plus") }
                Button(action: upload) { Label("Upload", systemImage: "arrow.up.doc") }
                Button(action: download) { Label("Download", systemImage: "arrow.down.doc") }.disabled(selection.isEmpty)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.disabled(selection.isEmpty)
            }
            .padding(12).background(.bar)
            Divider()

            Table(items, selection: $selection) {
                TableColumn("Name") { i in
                    Label(i.name, systemImage: i.isDir ? "folder.fill" : "doc")
                        .foregroundStyle(i.isDir ? Color.accentColor : Color.primary)
                }
                TableColumn("Size") { i in Text(i.isDir ? "—" : Double(i.size).diskString).foregroundStyle(.secondary) }.width(80)
                TableColumn("Modified") { i in Text(i.modified.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.width(150)
                TableColumn("Permissions") { i in Text(i.perms).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }.width(100)
            }
            .contextMenu(forSelectionType: String.self) { sel in
                if let n = sel.first, let i = items.first(where: { $0.name == n }) {
                    if i.isDir { Button("Open") { go(join(resolved, n)) } } else { Button("Preview") { showPreview(i) } }
                    Button("Download") { selection = sel; download() }
                    Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(join(resolved, n), forType: .string) }
                }
            } primaryAction: { sel in
                guard let n = sel.first, let i = items.first(where: { $0.name == n }) else { return }
                if i.isDir { go(join(resolved, n)) } else { showPreview(i) }
            }
            .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(6) } }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)

            if !status.isEmpty || loading {
                HStack { if loading { ProgressView().controlSize(.small) }; Text(status).font(.caption).foregroundStyle(.secondary); Spacer() }
                    .padding(8).background(.bar)
            }
        }
        .task { await load("~") }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { mkdir() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(selection.count) item(s) on \(machine.name)? This cannot be undone.", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { delete() }
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            VStack(alignment: .leading) {
                HStack { Text(preview?.0 ?? "").font(.headline); Spacer(); Button("Done") { preview = nil }.keyboardShortcut(.defaultAction) }
                OutputBox(text: preview?.1 ?? "", minHeight: 400)
            }
            .padding(20).frame(width: 760, height: 520)
        }
    }

    // MARK: Navigation

    private func parent(_ p: String) -> String {
        let u = (p as NSString).deletingLastPathComponent
        return u.isEmpty ? "/" : u
    }
    private func join(_ a: String, _ b: String) -> String { a == "/" ? "/" + b : a + "/" + b }
    private func go(_ p: String) { Task { await load(p) } }

    private func cdExpr(_ p: String) -> String {
        if p == "~" || p.isEmpty { return "\"$HOME\"" }
        if p.hasPrefix("~/") { return "\"$HOME\"/" + shq(String(p.dropFirst(2))) }
        return shq(p)
    }

    private func load(_ p: String) async {
        loading = true
        defer { loading = false }
        let script = """
        cd \(cdExpr(p)) 2>/dev/null || { echo "__ERR__cannot open this folder"; exit 1; }
        pwd -P
        stat -L -f '%HT%t%z%t%m%t%Sp%t%N' .[!.]* ..?* * 2>/dev/null
        """
        let r = await model.exec(machine, script, log: false)
        let lines = r.stdout.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard r.ok, let first = lines.first, !first.hasPrefix("__ERR__") else {
            status = r.stdout.contains("__ERR__") ? "Cannot open that folder (permissions?)." : String(r.text.prefix(200))
            return
        }
        resolved = first
        path = first
        items = lines.dropFirst().compactMap { l in
            let p = l.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 5, p[4] != "*" else { return nil }
            return Item(name: p[4], isDir: p[0] == "Directory", size: Int64(p[1]) ?? 0,
                        modified: Date(timeIntervalSince1970: TimeInterval(p[2]) ?? 0), perms: p[3])
        }.sorted { ($0.isDir ? 0 : 1, $0.name.lowercased()) < ($1.isDir ? 0 : 1, $1.name.lowercased()) }
        selection = []
        status = "\(items.count) items"
    }

    // MARK: Actions

    private func showPreview(_ i: Item) {
        guard i.size < 2_000_000 else { status = "File too large to preview — download it instead."; return }
        let file = join(resolved, i.name)
        Task {
            let r = await model.exec(machine, "head -c 60000 \(shq(file))", log: false)
            preview = (i.name, r.ok ? r.stdout : r.text)
        }
    }

    private func mkdir() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            let r = await model.exec(machine, "mkdir -p \(shq(join(resolved, name)))", label: "mkdir \(join(resolved, name))")
            status = r.ok ? "Folder created." : r.text
            await load(resolved)
        }
    }

    private func delete() {
        let names = selection.map { shq(join(resolved, $0)) }.joined(separator: " ")
        Task {
            let r = await model.exec(machine, "rm -rf \(names)", label: "rm -rf \(selection.joined(separator: ", ")) in \(resolved)")
            status = r.ok ? "Deleted." : r.text
            await load(resolved)
        }
    }

    private func download() {
        let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacHelm/\(machine.name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let names = Array(selection)
        Task {
            loading = true
            var failures: [String] = []
            for n in names {
                let r = await Remote(machine: machine).download(join(resolved, n), to: dest)
                if !r.ok { failures.append(r.text) }
            }
            loading = false
            status = failures.isEmpty ? "Downloaded \(names.count) item(s) to ~/Downloads/MacHelm/\(machine.name)" : failures.joined(separator: " ")
            if failures.isEmpty { NSWorkspace.shared.open(dest) }
        }
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { send(panel.urls) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { urls.append(url) }; group.leave() }
        }
        group.notify(queue: .main) { send(urls) }
        return true
    }

    private func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            loading = true
            var failures: [String] = []
            for u in urls {
                status = "Uploading \(u.lastPathComponent)…"
                let r = await Remote(machine: machine).upload(u, toDirectory: resolved)
                if !r.ok { failures.append(r.text) }
            }
            loading = false
            status = failures.isEmpty ? "Uploaded \(urls.count) item(s)." : failures.joined(separator: " ")
            await load(resolved)
        }
    }
}
