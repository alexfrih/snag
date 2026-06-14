import AppKit
import Combine
import Foundation

enum JobStatus: Equatable {
    case queued
    case downloading
    case done
    case failed(String)
}

final class Job: ObservableObject, Identifiable {
    let id = UUID()
    let url: String
    @Published var title: String
    @Published var status: JobStatus = .queued
    @Published var progress: Double = 0          // 0...1
    @Published var speed: String = ""
    @Published var eta: String = ""
    @Published var filePath: String?
    var pathLocked = false                        // final path known (post-merge); don't overwrite

    init(url: String) {
        self.url = url
        self.title = Job.initialTitle(url)
    }

    private static func initialTitle(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.replacingOccurrences(of: "www.", with: "") + " …"
    }
}

/// Accumulates piped bytes and emits complete newline-terminated lines.
final class LineBuffer {
    private var data = Data()
    private let onLine: (String) -> Void
    init(_ onLine: @escaping (String) -> Void) { self.onLine = onLine }
    func feed(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        data.append(chunk)
        while let nl = data.firstIndex(of: 0x0A) {
            let line = data.subdata(in: data.startIndex..<nl)
            data.removeSubrange(data.startIndex...nl)
            if let s = String(data: line, encoding: .utf8) { onLine(s) }
        }
    }
}

final class DownloadManager: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var activeCount: Int = 0
    @Published var toolMissing: Bool = false

    private let ytDlp: String?
    private let ffmpegDir: String?
    private var processes: [UUID: Process] = [:]

    init() {
        let home = NSHomeDirectory()
        ytDlp = Tools.resolve("yt-dlp", candidates: [
            "/opt/homebrew/bin/yt-dlp",
            "/opt/homebrew/Caskroom/miniconda/base/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "\(home)/.local/bin/yt-dlp",
        ])
        let ffmpeg = Tools.resolve("ffmpeg", candidates: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ])
        ffmpegDir = ffmpeg.map { ($0 as NSString).deletingLastPathComponent }
        toolMissing = (ytDlp == nil)
    }

    var downloadsDir: String {
        NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
            ?? (NSHomeDirectory() + "/Downloads")
    }

    // MARK: - Job control

    func add(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let job = Job(url: trimmed)
        jobs.insert(job, at: 0)
        start(job)
    }

    func retry(_ job: Job) {
        job.status = .queued
        job.progress = 0
        job.speed = ""
        job.eta = ""
        job.filePath = nil
        job.pathLocked = false
        start(job)
    }

    func remove(_ job: Job) {
        if let p = processes[job.id], p.isRunning { p.terminate() }
        processes[job.id] = nil
        jobs.removeAll { $0.id == job.id }
        recomputeActive()
    }

    func clearFinished() {
        for job in jobs where job.status == .downloading || job.status == .queued { continue }
        jobs.removeAll { $0.status != .downloading && $0.status != .queued }
    }

    // MARK: - Download

    private func start(_ job: Job) {
        guard let yt = ytDlp else {
            job.status = .failed("yt-dlp not found — install with: brew install yt-dlp")
            return
        }
        job.status = .downloading
        job.progress = 0
        recomputeActive()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: yt)

        var args: [String] = [
            "--newline",
            "--no-playlist",
            "--progress-template", "PROG:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b",
            "-o", "%(title)s.%(ext)s",
            "-P", downloadsDir,
        ]
        if let dir = ffmpegDir { args += ["--ffmpeg-location", dir] }
        let host = (URL(string: job.url)?.host ?? "").lowercased()
        if host.contains("x.com") || host.contains("twitter.com") {
            args += ["--no-check-certificates"]
        }
        args.append(job.url)
        proc.arguments = args

        // GUI apps start with a bare PATH; give yt-dlp a chance to find ffmpeg too.
        var env = ProcessInfo.processInfo.environment
        let ytDir = (yt as NSString).deletingLastPathComponent
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", ytDir, existing].joined(separator: ":")
        proc.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let outBuf = LineBuffer { [weak self, weak job] line in self?.handle(line, job) }
        let errBuf = LineBuffer { [weak self, weak job] line in self?.handle(line, job) }
        outPipe.fileHandleForReading.readabilityHandler = { h in outBuf.feed(h.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { h in errBuf.feed(h.availableData) }

        proc.terminationHandler = { [weak self, weak job] p in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self = self, let job = job else { return }
                self.processes[job.id] = nil
                if case .failed = job.status {
                    // keep the captured ERROR message
                } else if p.terminationStatus == 0 {
                    job.progress = 1
                    job.status = .done
                } else {
                    job.status = .failed("Download failed (exit \(p.terminationStatus))")
                }
                self.recomputeActive()
            }
        }

        do {
            try proc.run()
            processes[job.id] = proc
        } catch {
            job.status = .failed(error.localizedDescription)
            recomputeActive()
        }
    }

    private func recomputeActive() {
        activeCount = jobs.filter { $0.status == .downloading }.count
    }

    // MARK: - Output parsing

    private func handle(_ raw: String, _ jobRef: Job?) {
        guard let job = jobRef else { return }
        let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
        guard !line.isEmpty else { return }

        if line.hasPrefix("PROG:") {
            let parts = String(line.dropFirst(5)).components(separatedBy: "|")
            let pct = Self.parsePercent(parts.first ?? "")
            let speed = parts.count > 1 ? clean(parts[1]) : ""
            let eta = parts.count > 2 ? clean(parts[2]) : ""
            DispatchQueue.main.async {
                if let pct = pct { job.progress = pct }
                if !speed.isEmpty { job.speed = speed }
                if !eta.isEmpty { job.eta = eta }
            }
            return
        }

        if let r = line.range(of: "Merging formats into \"") {
            let rest = line[r.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                setFile(String(rest[..<end]), job, locked: true)
            }
        } else if let r = line.range(of: "Destination: ") {
            setFile(String(line[r.upperBound...]), job, locked: false)
        } else if line.contains(" has already been downloaded"),
                  let r = line.range(of: "] "),
                  let end = line.range(of: " has already been downloaded") {
            setFile(String(line[r.upperBound..<end.lowerBound]), job, locked: true)
        } else if let r = line.range(of: "ERROR:") {
            let msg = String(line[r.lowerBound...])
            DispatchQueue.main.async {
                job.status = .failed(msg)
                self.recomputeActive()
            }
        }
    }

    /// Record the destination file. Intermediate per-stream temps (Title.f137.mp4)
    /// refine the displayed title but are not used as the reveal target.
    private func setFile(_ path: String, _ job: Job, locked: Bool) {
        let title = Self.cleanTitle(path)
        let isTemp = path.range(of: "\\.f\\d+\\.[^.]+$", options: .regularExpression) != nil
        DispatchQueue.main.async {
            if job.pathLocked && !locked { return }
            if !title.isEmpty { job.title = title }
            if locked || !isTemp { job.filePath = path }
            if locked { job.pathLocked = true }
        }
    }

    private func clean(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return (t == "Unknown" || t == "N/A") ? "" : t
    }

    static func parsePercent(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard let v = Double(t) else { return nil }
        return max(0, min(1, v / 100))
    }

    static func cleanTitle(_ path: String) -> String {
        var name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if let r = name.range(of: "\\.f\\d+$", options: .regularExpression) {
            name.removeSubrange(r)
        }
        return name
    }
}
