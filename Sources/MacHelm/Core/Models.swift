import SwiftUI

enum Accent: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, orange, green, teal, red, indigo
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        case .red: .red
        case .indigo: .indigo
        }
    }
}

struct Machine: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var user: String
    var port: Int = 22
    var group: String = "My Macs"
    var icon: String = "laptopcomputer"
    var accent: Accent = .blue
    var macAddress: String = ""
    var isLocal: Bool = false
    var notes: String = ""

    var sshTarget: String { "\(user)@\(host)" }

    static let icons = ["laptopcomputer", "macbook", "desktopcomputer", "macmini", "macpro.gen3", "display", "server.rack", "externaldrive"]
}

struct Snippet: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var icon: String = "terminal"
    var builtin = false

    static let builtins: [Snippet] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "System overview", command: "uname -a; sw_vers; uptime", icon: "info.circle", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Disk usage by folder", command: "du -sh ~/* 2>/dev/null | sort -rh | head -15", icon: "internaldrive", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Top CPU processes", command: "ps -Ao pcpu,pid,comm -r | head -11", icon: "cpu", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Top memory processes", command: "ps -Ao pmem,pid,comm -m | head -11", icon: "memorychip", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Pending software updates", command: "softwareupdate -l 2>&1", icon: "arrow.down.circle", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, name: "Battery health", command: "system_profiler SPPowerDataType | grep -E 'Cycle Count|Condition|Maximum Capacity|Charging'", icon: "battery.100", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, name: "Network interfaces", command: "ifconfig | grep -E '^[a-z0-9]+:|inet '", icon: "network", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!, name: "Listening ports", command: "lsof -iTCP -sTCP:LISTEN -nP | head -30", icon: "point.3.connected.trianglepath.dotted", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, name: "Login items", command: "osascript -e 'tell application \"System Events\" to get the name of every login item'", icon: "person.badge.key", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, name: "Security posture", command: "fdesetup status; csrutil status; /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate", icon: "lock.shield", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, name: "Time Machine status", command: "tmutil status | head -12; tmutil latestbackup", icon: "clock.arrow.circlepath", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!, name: "Who is logged in", command: "who; echo; last -8", icon: "person.2", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!, name: "Homebrew upgrade", command: "brew update && brew upgrade", icon: "shippingbox", builtin: true),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!, name: "Restart Finder & Dock", command: "killall Finder Dock; echo done", icon: "arrow.clockwise", builtin: true),
    ]
}

struct Automation: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var machineIDs: [UUID] = []
    var group: String?          // when set, targets every machine in this group
    var intervalMinutes: Int = 60
    var enabled = true
    var notifyOnFailure = true
    var lastRun: Date?
    var lastSummary: String?
}

struct ActivityEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var machine: String
    var command: String
    var status: Int32
    var output: String
}

enum MachineStatus: String {
    case unknown, checking, online, offline, authRequired

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .checking: "Checking…"
        case .online: "Online"
        case .offline: "Offline"
        case .authRequired: "Needs key"
        }
    }
    var color: Color {
        switch self {
        case .online: .green
        case .offline: .red
        case .authRequired: .orange
        default: .gray
        }
    }
}

struct Runtime {
    var status: MachineStatus = .unknown
    var stats: Stats?
    var error: String?
    var lastSeen: Date?
    var cpuHistory: [Double] = []
    var memHistory: [Double] = []
}

struct Stats: Equatable {
    var host = "", os = "", build = "", model = "", chip = "", user = "", ip = "", mac = ""
    var cores = 0
    var memTotal = 0.0, memUsed = 0.0
    var diskTotal = 0.0, diskFree = 0.0
    var cpu = 0.0          // 0...100
    var load = 0.0
    var uptime: TimeInterval = 0
    var battery: Int?
    var charging = false
    var onAC = false
    var batteryTime: String?

    var memFraction: Double { memTotal > 0 ? memUsed / memTotal : 0 }
    var diskFraction: Double { diskTotal > 0 ? (diskTotal - diskFree) / diskTotal : 0 }

    /// Shell script whose key=value output `init?(parsing:)` understands. Runs under plain /bin/sh.
    static let script = #"""
    export LC_ALL=C
    echo "host=$(scutil --get ComputerName 2>/dev/null || hostname)"
    echo "os=$(sw_vers -productVersion)"
    echo "build=$(sw_vers -buildVersion)"
    echo "model=$(sysctl -n hw.model)"
    echo "chip=$(sysctl -n machdep.cpu.brand_string)"
    echo "cores=$(sysctl -n hw.ncpu)"
    echo "memTotal=$(sysctl -n hw.memsize)"
    echo "boot=$(sysctl -n kern.boottime | sed 's/.*{ sec = \([0-9]*\).*/\1/')"
    echo "now=$(date +%s)"
    echo "cpu=$(ps -A -o %cpu= | awk '{s+=$1} END {printf "%.1f", s}')"
    echo "load=$(sysctl -n vm.loadavg | awk '{print $2}')"
    vm_stat | awk '/page size of/ {ps=$8} /Pages active/ {a=$3} /Pages wired/ {w=$4} /occupied by compressor/ {c=$5} END {printf "memUsed=%d\n", (a+w+c)*ps}'
    df -k / | awk 'NR==2 {print "diskTotal=" $2*1024; print "diskFree=" $4*1024}'
    echo "batt=$(pmset -g batt 2>/dev/null | tr '\n' ' ')"
    echo "ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)"
    echo "mac=$(ifconfig en0 2>/dev/null | awk '/ether/{print $2}')"
    echo "user=$(id -un)"
    """#

    init?(parsing text: String) {
        var kv: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let i = line.firstIndex(of: "=") else { continue }
            kv[String(line[..<i])] = String(line[line.index(after: i)...])
        }
        guard kv["os"] != nil else { return nil }
        host = kv["host"] ?? ""
        os = kv["os"] ?? ""
        build = kv["build"] ?? ""
        model = kv["model"] ?? ""
        chip = kv["chip"] ?? ""
        user = kv["user"] ?? ""
        ip = kv["ip"] ?? ""
        mac = kv["mac"] ?? ""
        cores = Int(kv["cores"] ?? "") ?? 1
        memTotal = Double(kv["memTotal"] ?? "") ?? 0
        memUsed = Double(kv["memUsed"] ?? "") ?? 0
        diskTotal = Double(kv["diskTotal"] ?? "") ?? 0
        diskFree = Double(kv["diskFree"] ?? "") ?? 0
        cpu = min(100, max(0, (Double(kv["cpu"] ?? "") ?? 0) / Double(max(cores, 1))))
        load = Double(kv["load"] ?? "") ?? 0
        if let b = Double(kv["boot"] ?? ""), let n = Double(kv["now"] ?? "") { uptime = max(0, n - b) }
        if let batt = kv["batt"], batt.contains("InternalBattery") {
            battery = Int(Self.match(#"(\d+)%"#, in: batt) ?? "")
            let lower = batt.lowercased()
            charging = lower.contains("charging") && !lower.contains("discharging")
            onAC = batt.contains("AC Power")
            batteryTime = Self.match(#"(\d+:\d+) remaining"#, in: batt)
        }
    }

    private static func match(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}

extension Double {
    var bytesString: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory) }
    var diskString: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) }
}

extension TimeInterval {
    var uptimeString: String {
        let s = Int(self), d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
