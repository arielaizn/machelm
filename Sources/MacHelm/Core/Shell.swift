import Foundation

struct ShellResult {
    var data = Data()
    var stderr = ""
    var status: Int32 = 0

    var stdout: String { String(decoding: data, as: UTF8.self) }
    var ok: Bool { status == 0 }

    /// stdout + stderr, trimmed — what a human wants to read.
    var text: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Single-quote a string for POSIX shells.
func shq(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Escape a string for use inside an AppleScript string literal.
func appleScriptEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

enum Shell {
    static func run(_ exe: String, _ args: [String], stdin: String? = nil,
                    env: [String: String] = [:], timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ShellResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(exe, args, stdin: stdin, env: env, timeout: timeout))
            }
        }
    }

    static func runSync(_ exe: String, _ args: [String], stdin: String? = nil,
                        env: [String: String] = [:], timeout: TimeInterval = 30) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        do { try p.run() } catch {
            return ShellResult(data: Data(), stderr: error.localizedDescription, status: -1)
        }
        let outBox = Box(Data()), errBox = Box(Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outBox.value = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errBox.value = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if let stdin { try? inp.fileHandleForWriting.write(contentsOf: Data(stdin.utf8)) }
        try? inp.fileHandleForWriting.close()

        let timedOut = Box(false)
        let killer = DispatchWorkItem { if p.isRunning { timedOut.value = true; p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        group.wait()
        var stderr = String(decoding: errBox.value, as: UTF8.self)
        if timedOut.value { stderr += "\nTimed out after \(Int(timeout))s" }
        return ShellResult(data: outBox.value, stderr: stderr, status: timedOut.value ? 124 : p.terminationStatus)
    }
}

/// A running process whose output is streamed as it arrives (stdout + stderr merged).
final class LiveProcess: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()

    var isRunning: Bool { process.isRunning }

    init(exe: String, args: [String], stdin: String?, env: [String: String] = [:],
         onOutput: @escaping @Sendable (String) -> Void,
         onExit: @escaping @Sendable (Int32) -> Void) {
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        process.standardOutput = pipe
        process.standardError = pipe
        let inPipe = Pipe()
        process.standardInput = inPipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if !d.isEmpty { onOutput(String(decoding: d, as: UTF8.self)) }
        }
        process.terminationHandler = { [pipe] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            if !rest.isEmpty { onOutput(String(decoding: rest, as: UTF8.self)) }
            onExit(p.terminationStatus)
        }
        do { try process.run() } catch {
            onOutput("\(error.localizedDescription)\n")
            onExit(-1)
            return
        }
        if let stdin { try? inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8)) }
        try? inPipe.fileHandleForWriting.close()
    }

    func terminate() { if process.isRunning { process.terminate() } }
}
