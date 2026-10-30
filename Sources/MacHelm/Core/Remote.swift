import Foundation
import AppKit

/// Everything that talks to a machine goes through here: SSH with connection multiplexing for remote
/// Macs, or a plain local shell for "This Mac".
struct Remote {
    let machine: Machine

    static let controlDir: String = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacHelm/cm")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }()

    var sshOptions: [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=6",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=15",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(Self.controlDir)/%C",
            "-o", "ControlPersist=180",
            "-i", KeyManager.privateKeyPath,
        ]
    }

    private var sshArgs: [String] { ["-p", "\(machine.port)"] + sshOptions + [machine.sshTarget] }

    private func launch(login: Bool) -> (exe: String, args: [String]) {
        if machine.isLocal { return login ? ("/bin/zsh", ["-l", "-s"]) : ("/bin/sh", ["-s"]) }
        return ("/usr/bin/ssh", sshArgs + [login ? "/bin/zsh -l -s" : "/bin/sh -s"])
    }

    /// Run a script (fed over stdin) and wait for the result.
    func run(_ script: String, login: Bool = false, timeout: TimeInterval = 30) async -> ShellResult {
        let l = launch(login: login)
        return await Shell.run(l.exe, l.args, stdin: script, timeout: timeout)
    }

    /// Run a script and stream its output.
    func stream(_ script: String, login: Bool = true,
                onOutput: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> LiveProcess {
        let l = launch(login: login)
        return LiveProcess(exe: l.exe, args: l.args, stdin: script, onOutput: onOutput, onExit: onExit)
    }

    func download(_ remotePath: String, to local: URL) async -> ShellResult {
        if machine.isLocal { return await Shell.run("/bin/cp", ["-R", remotePath, local.path]) }
        return await Shell.run("/usr/bin/scp", ["-r", "-P", "\(machine.port)"] + sshOptions + ["\(machine.sshTarget):\(remotePath)", local.path], timeout: 900)
    }

    func upload(_ local: URL, toDirectory dir: String) async -> ShellResult {
        if machine.isLocal { return await Shell.run("/bin/cp", ["-R", local.path, dir]) }
        let dest = dir.hasSuffix("/") ? dir : dir + "/"
        return await Shell.run("/usr/bin/scp", ["-r", "-P", "\(machine.port)"] + sshOptions + [local.path, "\(machine.sshTarget):\(dest)"], timeout: 900)
    }

    /// Open an interactive ssh session in Terminal.app.
    func openInTerminal(remoteCommand: String? = nil) {
        var cmd = ""
        if !machine.isLocal {
            cmd = "ssh -p \(machine.port) -i \(shq(KeyManager.privateKeyPath)) -o StrictHostKeyChecking=accept-new "
            if remoteCommand != nil { cmd += "-t " }
            cmd += machine.sshTarget
            if let r = remoteCommand { cmd += " " + shq(r) }
        } else if let r = remoteCommand { cmd = r }
        let source = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscape(cmd))"
        end tell
        """
        Task.detached { _ = await Shell.run("/usr/bin/osascript", ["-e", source], timeout: 15) }
    }

    func openScreenSharing() {
        let host = machine.isLocal ? "localhost" : machine.host
        if let url = URL(string: "vnc://\(machine.user)@\(host)") { NSWorkspace.shared.open(url) }
    }
}
