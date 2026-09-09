import Foundation

struct ProcessOutcome {
    let code: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRun {
    /// Run a binary to completion and capture both streams. Blocking — keep it
    /// off the main thread. A non-nil `timeout` kills the process (and returns
    /// code 124) if it outlives it; a wedged engine shouldn't hang a conversion
    /// forever.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String],
                    cwd: URL? = nil, env: [String: String]? = nil,
                    timeout: TimeInterval? = nil) -> ProcessOutcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env {
            p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        let lock = NSLock()
        var outData = Data(), errData = Data()
        let readers = DispatchGroup()

        func drain(_ pipe: Pipe, into keep: @escaping (Data) -> Void) {
            readers.enter()
            let h = pipe.fileHandleForReading
            DispatchQueue.global(qos: .userInitiated).async {
                while case let chunk = h.availableData, !chunk.isEmpty { keep(chunk) }
                readers.leave()
            }
        }
        drain(outPipe) { d in lock.lock(); outData.append(d); lock.unlock() }
        drain(errPipe) { d in lock.lock(); errData.append(d); lock.unlock() }

        do {
            try p.run()
        } catch {
            return ProcessOutcome(code: -1, stdout: "", stderr: "launch failed: \(error.localizedDescription)")
        }

        var timedOut = false
        if let timeout {
            let deadline = DispatchWorkItem { timedOut = true; p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            p.waitUntilExit()
            deadline.cancel()
        } else {
            p.waitUntilExit()
        }
        readers.wait()

        return ProcessOutcome(
            code: timedOut ? 124 : p.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: timedOut ? "timed out after \(Int(timeout ?? 0))s" : String(decoding: errData, as: UTF8.self)
        )
    }
}
