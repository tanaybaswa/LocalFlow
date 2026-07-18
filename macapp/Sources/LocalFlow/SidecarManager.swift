import Foundation

enum SidecarError: LocalizedError {
    case binaryMissing(URL)
    case modelMissing(URL)
    case launchFailed(String)
    case notHealthy

    var errorDescription: String? {
        switch self {
        case .binaryMissing(let u): return "whisper-server not found at \(u.path)"
        case .modelMissing(let u): return "Model not found at \(u.path)"
        case .launchFailed(let s): return "Failed to start whisper-server: \(s)"
        case .notHealthy: return "whisper-server did not become healthy in time"
        }
    }
}

@MainActor
final class SidecarManager {
    private(set) var isReady = false
    private var process: Process?
    private let port: Int
    private let modelURL: URL
    private let binaryURL: URL

    init(
        port: Int = AppPaths.sidecarPort,
        modelURL: URL = AppPaths.modelURL,
        binaryURL: URL = AppPaths.whisperServerURL
    ) {
        self.port = port
        self.modelURL = modelURL
        self.binaryURL = binaryURL
    }

    func start() async throws {
        if isReady { return }

        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw SidecarError.binaryMissing(binaryURL)
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw SidecarError.modelMissing(modelURL)
        }

        // Kill any stale listener on our port
        await Self.killStale(port: port)

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = [
            "-m", modelURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--language", "en",
            "--convert",
            "-t", "8",
        ]
        var env = ProcessInfo.processInfo.environment
        let brewPaths = "/opt/homebrew/bin:/usr/local/bin"
        if let path = env["PATH"], !path.isEmpty {
            env["PATH"] = "\(brewPaths):\(path)"
        } else {
            env["PATH"] = "\(brewPaths):/usr/bin:/bin"
        }
        proc.environment = env

        // whisper-server --convert writes temp WAVs into CWD; GUI default CWD is often "/"
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalFlow-whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        proc.currentDirectoryURL = workDir

        let errPipe = Pipe()
        let outPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = outPipe
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isReady = false
                self?.process = nil
            }
        }

        do {
            try proc.run()
        } catch {
            throw SidecarError.launchFailed(error.localizedDescription)
        }
        process = proc

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if !proc.isRunning {
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw SidecarError.launchFailed(err.isEmpty ? "process exited early" : err)
            }
            if await Self.probeHealthy(port: port) {
                isReady = true
                return
            }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        stop()
        throw SidecarError.notHealthy
    }

    func stop() {
        guard let proc = process else { return }
        proc.terminate()
        // Give it a moment, then force
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if proc.isRunning { proc.interrupt() }
        }
        process = nil
        isReady = false
    }

    private static func probeHealthy(port: Int) async -> Bool {
        // POST a tiny empty request isn't ideal; GET / often 404 but connection success = up.
        // whisper-server serves something on / — try connecting to inference with OPTIONS or a HEAD.
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            // Any HTTP response means the server accepted the connection.
            return (resp as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }

    private static func killStale(port: Int) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", "tcp:\(port)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let pids = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isWhitespace)
                .compactMap { Int($0) } ?? []
            for pid in pids {
                kill(pid_t(pid), SIGTERM)
            }
            if !pids.isEmpty {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } catch {
            // ignore
        }
    }
}
