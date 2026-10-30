import SwiftUI

struct ControlsTab: View {
    @Environment(AppModel.self) private var model
    let machine: Machine

    @State private var result = ""
    @State private var volume = 40.0
    @State private var sayText = ""
    @State private var notifTitle = "MacHelm"
    @State private var notifBody = ""
    @State private var typeText = ""
    @State private var clipboard = ""
    @State private var confirm: PowerAction?
    @State private var caffeinateHours = 1

    enum PowerAction: String, Identifiable {
        case restart = "Restart", shutdown = "Shut Down"
        var id: String { rawValue }
        var script: String {
            switch self {
            case .restart: "osascript -e 'tell application \"System Events\" to restart'"
            case .shutdown: "osascript -e 'tell application \"System Events\" to shut down'"
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 170), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(text: "Power")
                LazyVGrid(columns: columns, spacing: 12) {
                    ActionTile(title: "Sleep", icon: "moon.zzz.fill", tint: .indigo) { run("sleep", "pmset sleepnow") }
                    ActionTile(title: "Sleep Display", icon: "display", tint: .purple) { run("display sleep", "pmset displaysleepnow") }
                    ActionTile(title: "Lock Screen", icon: "lock.fill", tint: .orange) {
                        run("lock screen", "osascript -e 'tell application \"System Events\" to keystroke \"q\" using {control down, command down}' 2>&1 || pmset displaysleepnow")
                    }
                    ActionTile(title: "Wake (WOL)", icon: "power", tint: .green) {
                        result = model.wake(machine) ? "Magic packet sent to \(machine.macAddress.isEmpty ? "the learned MAC" : machine.macAddress)." : "No valid MAC address known yet — it is learned automatically the first time the Mac is online."
                    }
                    ActionTile(title: "Restart", icon: "arrow.triangle.2.circlepath", tint: .blue) { confirm = .restart }
                    ActionTile(title: "Shut Down", icon: "poweroff", tint: .red) { confirm = .shutdown }
                    ActionTile(title: "Keep Awake \(caffeinateHours)h", icon: "cup.and.saucer.fill", tint: .brown) {
                        run("caffeinate \(caffeinateHours)h", "(nohup caffeinate -dimsu -t \(caffeinateHours * 3600) >/dev/null 2>&1 </dev/null &); echo \"Staying awake for \(caffeinateHours)h\"")
                    }
                    ActionTile(title: "Cancel Keep Awake", icon: "cup.and.saucer", tint: .gray) { run("stop caffeinate", "pkill caffeinate && echo stopped || echo 'nothing running'") }
                }
                Stepper("Keep-awake duration: \(caffeinateHours) h", value: $caffeinateHours, in: 1...24).font(.caption)

                SectionTitle(text: "Sound & speech")
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $volume, in: 0...100) { editing in
                            if !editing { run("volume \(Int(volume))", "osascript -e 'set volume output volume \(Int(volume))'") }
                        }
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        Text("\(Int(volume))").monospacedDigit().frame(width: 30)
                        Button("Mute") { run("mute", "osascript -e 'set volume output muted true'") }
                    }
                    HStack {
                        TextField("Make the Mac speak…", text: $sayText).textFieldStyle(.roundedBorder).onSubmit(say)
                        Button("Say", action: say).disabled(sayText.isEmpty)
                    }
                }
                .card()

                SectionTitle(text: "Message the user")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Title", text: $notifTitle).textFieldStyle(.roundedBorder).frame(width: 180)
                        TextField("Message", text: $notifBody).textFieldStyle(.roundedBorder).onSubmit(notify)
                        Button("Send Notification", action: notify).disabled(notifBody.isEmpty)
                    }
                }
                .card()

                SectionTitle(text: "Keyboard & clipboard")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Type this text on the remote Mac…", text: $typeText).textFieldStyle(.roundedBorder)
                        Button("Type") {
                            run("type text", "osascript -e \(shq("tell application \"System Events\" to keystroke \"\(appleScriptEscape(typeText))\""))")
                        }.disabled(typeText.isEmpty)
                    }
                    HStack {
                        TextField("Clipboard", text: $clipboard).textFieldStyle(.roundedBorder)
                        Button("Fetch Remote") {
                            Task { let r = await model.exec(machine, "pbpaste", label: "read clipboard"); clipboard = r.stdout; result = r.ok ? "Clipboard read." : r.text }
                        }
                        Button("Push to Remote") { run("write clipboard", "printf '%s' \(shq(clipboard)) | pbcopy") }.disabled(clipboard.isEmpty)
                        Button("Use Mine") { clipboard = NSPasteboard.general.string(forType: .string) ?? "" }
                    }
                }
                .card()

                SectionTitle(text: "Quick actions")
                LazyVGrid(columns: columns, spacing: 12) {
                    ActionTile(title: "Toggle Dark Mode", icon: "circle.lefthalf.filled", tint: .indigo) {
                        run("toggle dark mode", "osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'")
                    }
                    ActionTile(title: "Show Desktop IP", icon: "network", tint: .teal) { run("ip", "ipconfig getifaddr en0 || ipconfig getifaddr en1") }
                    ActionTile(title: "Restart Finder", icon: "folder", tint: .blue) { run("restart Finder", "killall Finder; echo done") }
                    ActionTile(title: "Restart Dock", icon: "dock.rectangle", tint: .cyan) { run("restart Dock", "killall Dock; echo done") }
                    ActionTile(title: "Empty Trash", icon: "trash", tint: .red) { run("empty trash", "osascript -e 'tell application \"Finder\" to empty trash'") }
                    ActionTile(title: "Software Update", icon: "arrow.down.circle", tint: .green) { run("softwareupdate -l", "softwareupdate -l 2>&1", timeout: 120) }
                }

                if !result.isEmpty {
                    SectionTitle(text: "Result")
                    OutputBox(text: result, minHeight: 60)
                }
            }
            .padding(24)
        }
        .confirmationDialog("\(confirm?.rawValue ?? "") \(machine.name)?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            if let c = confirm { Button(c.rawValue, role: .destructive) { run(c.rawValue.lowercased(), c.script) } }
        } message: {
            Text("The Mac will be unreachable until it is started again.")
        }
    }

    private func run(_ label: String, _ script: String, timeout: TimeInterval = 30) {
        Task {
            result = "Running…"
            let r = await model.exec(machine, script, label: label, timeout: timeout)
            result = r.text.isEmpty ? (r.ok ? "Done." : "Failed (exit \(r.status)).") : r.text
        }
    }

    private func say() { run("say", "say \(shq(sayText))"); sayText = "" }

    private func notify() {
        let s = "display notification \"\(appleScriptEscape(notifBody))\" with title \"\(appleScriptEscape(notifTitle))\" sound name \"Glass\""
        run("notify", "osascript -e \(shq(s))")
        notifBody = ""
    }
}
