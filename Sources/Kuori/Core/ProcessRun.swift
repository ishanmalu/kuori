import Foundation

struct ProcessOutcome {
    let code: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRun {
    /// Run a binary to completion, capturing both streams. Blocking; call off
    /// the main thread from the GUI.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], cwd: URL? = nil,
                    env: [String: String]? = nil) -> ProcessOutcome {
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
        let group = DispatchGroup()

        func drain(_ pipe: Pipe, _ append: @escaping (Data) -> Void) {
            group.enter()
            let h = pipe.fileHandleForReading
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    let chunk = h.availableData
                    if chunk.isEmpty { break }
                    append(chunk)
                }
                group.leave()
            }
        }
        drain(outPipe) { d in lock.lock(); outData.append(d); lock.unlock() }
        drain(errPipe) { d in lock.lock(); errData.append(d); lock.unlock() }

        do {
            try p.run()
        } catch {
            return ProcessOutcome(code: -1, stdout: "", stderr: "launch failed: \(error.localizedDescription)")
        }
        p.waitUntilExit()
        group.wait()

        return ProcessOutcome(
            code: p.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
