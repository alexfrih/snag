import Foundation

/// Resolves CLI tools (yt-dlp, ffmpeg) for a GUI app, which does NOT inherit
/// the user's shell PATH. We probe known install locations first, then fall
/// back to asking a login shell (which sources ~/.zshrc, where conda/brew live).
enum Tools {
    static func resolve(_ name: String, candidates: [String]) -> String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return loginShellWhich(name)
    }

    private static func loginShellWhich(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lic", "command -v \(name)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
