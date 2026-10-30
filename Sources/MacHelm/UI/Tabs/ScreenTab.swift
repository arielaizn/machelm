import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ScreenTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    @State private var image: NSImage?
    @State private var auto = false
    @State private var quality = 1600
    @State private var error = ""
    @State private var loading = false
    @State private var lastUpdate: Date?

    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { Remote(machine: machine).openScreenSharing() } label: { Label("Control Screen (VNC)", systemImage: "cursorarrow.motionlines") }
                    .buttonStyle(.borderedProminent)
                Divider().frame(height: 22)
                Button { Task { await capture() } } label: { Label(loading ? "Capturing…" : "Snapshot", systemImage: "camera") }
                    .buttonStyle(.bordered).disabled(loading)
                Toggle("Live (2s)", isOn: $auto).toggleStyle(.switch)
                Picker("Size", selection: $quality) {
                    Text("Fast").tag(1000); Text("Balanced").tag(1600); Text("Sharp").tag(2800)
                }.pickerStyle(.segmented).frame(width: 220)
                Spacer()
                if image != nil {
                    Button { save() } label: { Label("Save…", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
                }
            }
            .padding(14).background(.bar)
            Divider()
            ZStack {
                Color.black.opacity(0.35)
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(12)
                } else {
                    ContentUnavailableView {
                        Label("No snapshot yet", systemImage: "display")
                    } description: {
                        Text(error.isEmpty ? "Take a snapshot for a quick look, or use Control Screen for full mouse and keyboard control through macOS Screen Sharing." : error)
                    }
                }
            }
            if let lastUpdate {
                Text("Updated \(lastUpdate.formatted(date: .omitted, time: .standard))").font(.caption2).foregroundStyle(.secondary).padding(6)
            }
        }
        .onReceive(ticker) { _ in if auto, !loading { Task { await capture() } } }
        .onChange(of: auto) { _, on in if on { Task { await capture() } } }
    }

    private func capture() async {
        loading = true
        defer { loading = false }
        let script = """
        f="${TMPDIR:-/tmp}/.machelm-shot.jpg"
        screencapture -x -t jpg "$f" 2>&1 || exit 2
        sips -Z \(quality) -s formatOptions 60 "$f" >/dev/null 2>&1
        cat "$f"; rm -f "$f"
        """
        let r = await model.exec(machine, script, timeout: 40, log: false)
        if r.ok, let img = NSImage(data: r.data) {
            image = img
            error = ""
            lastUpdate = Date()
        } else {
            auto = false
            error = r.text.isEmpty
                ? "Capture failed. The target Mac needs a logged-in desktop session and Screen Recording permission for sshd-keygen-wrapper."
                : "Capture failed: \(String(r.stderr.prefix(200)))"
        }
    }

    private func save() {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "\(machine.name) screenshot.jpg"
        if panel.runModal() == .OK, let url = panel.url { try? jpg.write(to: url) }
    }
}
