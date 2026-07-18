import Foundation

enum AppPaths {
    static let sidecarPort = 12321
    static let modelFileName = "ggml-large-v3.bin"

    /// Repo root: …/local-speech-to-text (models/ lives here)
    static var projectRoot: URL {
        if let env = ProcessInfo.processInfo.environment["LOCALFLOW_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        // From LocalFlow.app/Contents/MacOS/LocalFlow → …/macapp/dist/LocalFlow.app/…
        // → project root local-speech-to-text/ (where models/ lives)
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var url = exe.deletingLastPathComponent() // MacOS
        for _ in 0..<5 { // Contents, .app, dist, macapp, project root
            url = url.deletingLastPathComponent()
        }
        return url
    }

    static var modelURL: URL {
        if let env = ProcessInfo.processInfo.environment["LOCALFLOW_MODEL"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return projectRoot.appendingPathComponent("models").appendingPathComponent(modelFileName)
    }

    static var whisperServerURL: URL {
        if let env = ProcessInfo.processInfo.environment["LOCALFLOW_WHISPER_SERVER"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let brew = URL(fileURLWithPath: "/opt/homebrew/bin/whisper-server")
        if FileManager.default.isExecutableFile(atPath: brew.path) { return brew }
        return URL(fileURLWithPath: "/usr/local/bin/whisper-server")
    }

    static var inferenceEndpoint: URL {
        URL(string: "http://127.0.0.1:\(sidecarPort)/inference")!
    }
}
