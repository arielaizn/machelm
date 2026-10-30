import SwiftUI
import UserNotifications
import ServiceManagement

enum SidebarItem: Hashable {
    case fleet, broadcast, scripts, automations, activity
    case machine(UUID)
}

struct BroadcastResult: Identifiable {
    let id: UUID          // machine id
    var machine: String
    var result: ShellResult?
}

enum Notifier {
    static func requestAuth() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil, UserDefaults.standard.object(forKey: "notify") as? Bool ?? true else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

@MainActor @Observable
final class AppModel {
    var machines: [Machine] = []
    var customSnippets: [Snippet] = []
    var automations: [Automation] = []
    var activity: [ActivityEntry] = []
    var runtime: [UUID: Runtime] = [:]

    var selection: SidebarItem? = .fleet
    var showAddSheet = false
    var editing: Machine?
    var showPalette = false
    var broadcastDraft = ""

    @ObservationIgnored private var started = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    var snippets: [Snippet] { Snippet.builtins + customSnippets }
    var groups: [String] { Array(Set(machines.map(\.group))).sorted() }
    var onlineCount: Int { machines.filter { runtime[$0.id]?.status == .online }.count }

    init() { load() }

    // MARK: Persistence

    private struct Persisted: Codable {
        var machines: [Machine] = []
        var snippets: [Snippet] = []
        var automations: [Automation] = []
        var activity: [ActivityEntry] = []
    }

    private var stateURL: URL { KeyManager.directory.appendingPathComponent("state.json") }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        machines = p.machines
        customSnippets = p.snippets
        automations = p.automations
        activity = p.activity
    }

    func save() {
        let p = Persisted(machines: machines, snippets: customSnippets, automations: automations, activity: activity)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(p).write(to: stateURL, options: .atomic)
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        await KeyManager.ensureKey()
        Notifier.requestAuth()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                await self.runDueAutomations()
                let stored = UserDefaults.standard.double(forKey: "pollInterval")
                try? await Task.sleep(for: .seconds(stored >= 5 ? stored : 15))
            }
        }
    }

    // MARK: Machines

    func machine(_ id: UUID) -> Machine? { machines.first { $0.id == id } }

    func upsert(_ m: Machine) {
        if let i = machines.firstIndex(where: { $0.id == m.id }) { machines[i] = m } else { machines.append(m) }
        save()
        Task { await refresh(m) }
    }

    func delete(_ m: Machine) {
        machines.removeAll { $0.id == m.id }
        runtime[m.id] = nil
        if selection == .machine(m.id) { selection = .fleet }
        save()
    }

    func addThisMac() {
        guard !machines.contains(where: \.isLocal) else { return }
        let m = Machine(name: Host.current().localizedName ?? "This Mac", host: "localhost", user: NSUserName(),
                        group: "Local", icon: "laptopcomputer", accent: .teal, isLocal: true)
        upsert(m)
        selection = .machine(m.id)
    }

    // MARK: Monitoring

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for m in machines { group.addTask { await self.refresh(m) } }
        }
    }

    func refresh(_ m: Machine) async {
        if runtime[m.id] == nil { runtime[m.id] = Runtime(status: .checking) }
        let r = await Remote(machine: m).run(Stats.script, timeout: 20)
        var rt = runtime[m.id] ?? Runtime()
        let before = rt.status
        if r.ok, let s = Stats(parsing: r.stdout) {
            rt.status = .online
            rt.stats = s
            rt.error = nil
            rt.lastSeen = Date()
            rt.cpuHistory = (rt.cpuHistory + [s.cpu]).suffix(60)
            rt.memHistory = (rt.memHistory + [s.memFraction * 100]).suffix(60)
            if let i = machines.firstIndex(where: { $0.id == m.id }) {
                var changed = false
                if machines[i].macAddress.isEmpty, !s.mac.isEmpty { machines[i].macAddress = s.mac; changed = true }
                if changed { save() }
            }
        } else {
            let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            rt.status = err.contains("Permission denied") ? .authRequired : .offline
            rt.error = err.isEmpty ? "Unreachable" : err
        }
        runtime[m.id] = rt
        if before == .online, rt.status != .online { Notifier.post("\(m.name) went offline", rt.error ?? "") }
        if before == .offline, rt.status == .online { Notifier.post("\(m.name) is back online", "Reachable again.") }
    }

    // MARK: Commands

    @discardableResult
    func exec(_ m: Machine, _ script: String, label: String? = nil, login: Bool = false,
              timeout: TimeInterval = 30, log: Bool = true) async -> ShellResult {
        let r = await Remote(machine: m).run(script, login: login, timeout: timeout)
        if log { record(m, label ?? script, r) }
        return r
    }

    func record(_ m: Machine, _ command: String, _ r: ShellResult) {
        let out = String(r.text.prefix(6000))
        activity.insert(.init(machine: m.name, command: String(command.prefix(500)), status: r.status, output: out), at: 0)
        if activity.count > 400 { activity.removeLast(activity.count - 400) }
        save()
    }

    func broadcast(_ command: String, to targets: [Machine], login: Bool = true) async -> [UUID: ShellResult] {
        await withTaskGroup(of: (UUID, ShellResult).self) { group in
            for m in targets {
                group.addTask { (m.id, await self.exec(m, command, login: login, timeout: 120)) }
            }
            var all: [UUID: ShellResult] = [:]
            for await (id, r) in group { all[id] = r }
            return all
        }
    }

    // MARK: Power & wake

    func wake(_ m: Machine) -> Bool {
        let mac = m.macAddress.isEmpty ? (runtime[m.id]?.stats?.mac ?? "") : m.macAddress
        return WakeOnLAN.send(mac: mac, subnetHint: runtime[m.id]?.stats?.ip)
    }

    // MARK: Automations

    func runDueAutomations() async {
        let now = Date()
        for a in automations where a.enabled {
            if let last = a.lastRun, now.timeIntervalSince(last) < Double(a.intervalMinutes) * 60 { continue }
            await run(automation: a)
        }
    }

    func targets(for a: Automation) -> [Machine] {
        if let g = a.group { return machines.filter { $0.group == g } }
        return machines.filter { a.machineIDs.contains($0.id) }
    }

    func run(automation a: Automation) async {
        let t = targets(for: a)
        let results = await broadcast(a.command, to: t)
        let failed = t.filter { !(results[$0.id]?.ok ?? false) }
        if let i = automations.firstIndex(where: { $0.id == a.id }) {
            automations[i].lastRun = Date()
            automations[i].lastSummary = t.isEmpty ? "No targets" : "\(t.count - failed.count)/\(t.count) succeeded"
            save()
        }
        if a.notifyOnFailure, !failed.isEmpty {
            Notifier.post("Automation “\(a.name)” failed", "On: " + failed.map(\.name).joined(separator: ", "))
        }
    }

    // MARK: Launch at login

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }
}
