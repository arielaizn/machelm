import SwiftUI

struct AppsTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    @State private var apps: [String] = []
    @State private var launchName = ""
    @State private var url = ""
    @State private var message = ""
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Launch an app")
                        HStack {
                            TextField("App name, e.g. Safari", text: $launchName).textFieldStyle(.roundedBorder).onSubmit(launch)
                            Button("Open", action: launch).disabled(launchName.isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Open a URL or file")
                        HStack {
                            TextField("https://…", text: $url).textFieldStyle(.roundedBorder).onSubmit(openURL)
                            Button("Open", action: openURL).disabled(url.isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: "Running apps (\(apps.count))")
                        Spacer()
                        if loading { ProgressView().controlSize(.small) }
                        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                    }
                    if apps.isEmpty {
                        Text(message.isEmpty ? "No GUI apps reported. The Mac needs a logged-in desktop session." : message)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(apps, id: \.self) { name in
                        HStack {
                            Image(systemName: "app.fill").foregroundStyle(.secondary)
                            Text(name)
                            Spacer()
                            Button("Quit") { quit(name, force: false) }.controlSize(.small)
                            Button("Force Quit", role: .destructive) { quit(name, force: true) }.controlSize(.small)
                        }
                        Divider()
                    }
                }
                .card()

                if !message.isEmpty && !apps.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(24)
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        let r = await model.exec(machine, "osascript -e 'tell application \"System Events\" to get name of every application process whose background only is false'", log: false)
        guard r.ok else { message = r.text; apps = []; return }
        apps = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ", ").filter { !$0.isEmpty }.sorted()
        message = ""
    }

    private func launch() {
        let n = launchName
        Task {
            let r = await model.exec(machine, "open -a \(shq(n))", label: "open -a \(n)")
            message = r.ok ? "Opened \(n)." : r.text
            launchName = ""
            try? await Task.sleep(for: .seconds(1)); await reload()
        }
    }

    private func openURL() {
        let u = url
        Task {
            let r = await model.exec(machine, "open \(shq(u))", label: "open \(u)")
            message = r.ok ? "Opened." : r.text
            url = ""
        }
    }

    private func quit(_ name: String, force: Bool) {
        Task {
            let script = force ? "pkill -9 -x \(shq(name))" : "osascript -e \(shq("tell application \"\(name)\" to quit"))"
            let r = await model.exec(machine, script, label: "\(force ? "force quit" : "quit") \(name)")
            message = r.ok ? "\(name) closed." : r.text
            try? await Task.sleep(for: .seconds(1)); await reload()
        }
    }
}
