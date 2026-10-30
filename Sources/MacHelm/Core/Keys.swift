import Foundation

/// MacHelm owns one ed25519 key pair; installing its public half on a Mac gives passwordless control.
enum KeyManager {
    static var directory: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacHelm")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var privateKeyPath: String { directory.appendingPathComponent("id_ed25519").path }
    static var publicKey: String {
        ((try? String(contentsOfFile: privateKeyPath + ".pub", encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func ensureKey() async {
        guard !FileManager.default.fileExists(atPath: privateKeyPath) else { return }
        _ = await Shell.run("/usr/bin/ssh-keygen", ["-t", "ed25519", "-N", "", "-C", "machelm@\(Host.current().localizedName ?? "mac")", "-f", privateKeyPath, "-q"])
    }

    static func regenerate() async {
        try? FileManager.default.removeItem(atPath: privateKeyPath)
        try? FileManager.default.removeItem(atPath: privateKeyPath + ".pub")
        await ensureKey()
    }

    /// Install our public key on `machine` using its account password. The password is only passed to
    /// ssh through a throw-away SSH_ASKPASS helper and is never stored.
    static func install(on machine: Machine, password: String) async -> ShellResult {
        await ensureKey()
        let blob = publicKey.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        guard !blob.isEmpty else { return ShellResult(stderr: "No public key available", status: 1) }

        let askpass = FileManager.default.temporaryDirectory.appendingPathComponent("machelm-askpass-\(UUID().uuidString).sh")
        do {
            try "#!/bin/sh\nprintf '%s\\n' \"$MACHELM_PW\"\n".write(to: askpass, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
        } catch { return ShellResult(stderr: error.localizedDescription, status: 1) }
        defer { try? FileManager.default.removeItem(at: askpass) }

        let script = """
        umask 077
        mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
        grep -qF \(shq(blob)) ~/.ssh/authorized_keys || printf '%s\\n' \(shq(publicKey)) >> ~/.ssh/authorized_keys
        echo "key installed"
        """
        let args = ["-p", "\(machine.port)",
                    "-o", "PubkeyAuthentication=no",
                    "-o", "PreferredAuthentications=password,keyboard-interactive",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ConnectTimeout=8",
                    "-o", "NumberOfPasswordPrompts=1",
                    "-o", "ControlPath=none",
                    machine.sshTarget, "sh -s"]
        return await Shell.run("/usr/bin/ssh", args, stdin: script,
                               env: ["SSH_ASKPASS": askpass.path, "SSH_ASKPASS_REQUIRE": "force", "MACHELM_PW": password, "DISPLAY": ":0"],
                               timeout: 30)
    }
}

enum WakeOnLAN {
    /// Broadcasts a magic packet. Returns false if the MAC is malformed or the socket fails.
    @discardableResult
    static func send(mac: String, subnetHint: String? = nil) -> Bool {
        let bytes = mac.split(whereSeparator: { ":-".contains($0) }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return false }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }

        var targets = ["255.255.255.255"]
        if let ip = subnetHint {
            let p = ip.split(separator: ".")
            if p.count == 4 { targets.append("\(p[0]).\(p[1]).\(p[2]).255") }
        }
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var okAny = false
        for target in targets {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(9).bigEndian
            addr.sin_addr.s_addr = inet_addr(target)
            let sent = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(sock, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if sent == packet.count { okAny = true }
        }
        return okAny
    }
}
