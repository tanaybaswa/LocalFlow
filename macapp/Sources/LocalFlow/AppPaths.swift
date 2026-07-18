import Foundation

enum AppPaths {
    static let sidecarPort = 12321
    static let modelFileName = "ggml-large-v3.bin"
    static let appSupportFolderName = "LocalFlow"

    /// `~/Library/Application Support/LocalFlow` — preferred when the app is in /Applications.
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    static var applicationSupportModelURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(modelFileName)
    }

    /// Best-effort repo / project root (dev builds under `macapp/dist/…`).
    static var projectRoot: URL? {
        if let env = ProcessInfo.processInfo.environment["LOCALFLOW_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return discoverDirectoryContainingModel(startingAt: executableURL)
    }

    static var modelURL: URL {
        if let env = ProcessInfo.processInfo.environment["LOCALFLOW_MODEL"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }

        let fm = FileManager.default
        let candidates: [URL] = [
            applicationSupportModelURL,
            projectRoot?
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(modelFileName),
        ].compactMap { $0 }

        if let hit = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            return hit
        }

        // Prefer Application Support in the error path so installs have a clear place to put the model.
        return applicationSupportModelURL
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

    // MARK: - Discovery

    private static var executableURL: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    }

    /// Walk up from the .app binary looking for `models/ggml-large-v3.bin`
    /// (works for `…/LocalFlow/macapp/dist/LocalFlow.app`, not for `/Applications`).
    private static func discoverDirectoryContainingModel(startingAt start: URL) -> URL? {
        let fm = FileManager.default
        var url = start.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = url
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(modelFileName)
            if fm.fileExists(atPath: candidate.path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }
}
