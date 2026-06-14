import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: DownloadManager
    let onQuit: () -> Void

    @State private var urlText = ""
    @FocusState private var fieldFocused: Bool
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider()
            if manager.toolMissing {
                toolMissingBanner
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .onReceive(NotificationCenter.default.publisher(for: .snagPopoverDidOpen)) { _ in
            onOpen()
        }
        .onAppear { onOpen() }
    }

    private func onOpen() {
        prefillFromClipboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fieldFocused = true }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("Paste a video URL", text: $urlText)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.down.circle.fill").font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSubmit: Bool {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("http")
    }

    private func submit() {
        guard canSubmit else { return }
        manager.add(urlString: urlText)
        urlText = ""
    }

    private func prefillFromClipboard() {
        guard urlText.isEmpty,
              let s = NSPasteboard.general.string(forType: .string) else { return }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("http"), !t.contains(" "), t.count < 2000 {
            urlText = t
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if manager.jobs.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("Paste a link to download it to your Downloads folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .padding(.horizontal, 24)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(manager.jobs) { job in
                        JobRow(job: job, manager: manager)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - Banners / footer

    private var toolMissingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("yt-dlp not found").font(.caption.bold())
                Text("brew install yt-dlp")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install yt-dlp", forType: .string)
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, new in LoginItem.setEnabled(new) }
            Spacer()
            if manager.jobs.contains(where: { $0.status != .downloading && $0.status != .queued }) {
                Button("Clear") { manager.clearFinished() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Job row

private struct JobRow: View {
    @ObservedObject var job: Job
    let manager: DownloadManager
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var statusIcon: some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle").foregroundStyle(Color.accentColor)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch job.status {
        case .queued:
            Text("Queued").font(.caption2).foregroundStyle(.secondary)
        case .downloading:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 4)
                Text(progressLabel).font(.caption2).foregroundStyle(.secondary)
            }
        case .done:
            Text("Saved to Downloads").font(.caption2).foregroundStyle(.green)
        case .failed(let msg):
            Text(msg).font(.caption2).foregroundStyle(.red)
                .lineLimit(2).truncationMode(.tail)
        }
    }

    private var progressLabel: String {
        var bits = ["\(Int((job.progress * 100).rounded()))%"]
        if !job.speed.isEmpty { bits.append(job.speed) }
        if !job.eta.isEmpty { bits.append("ETA \(job.eta)") }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        switch job.status {
        case .downloading:
            Button { manager.remove(job) } label: {
                Image(systemName: "stop.circle")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Cancel")
        case .done:
            HStack(spacing: 8) {
                Button("Reveal") { reveal() }.buttonStyle(.link).font(.caption)
                if hovering { removeButton }
            }
        case .failed:
            HStack(spacing: 8) {
                Button("Retry") { manager.retry(job) }.buttonStyle(.link).font(.caption)
                if hovering { removeButton }
            }
        case .queued:
            if hovering { removeButton }
        }
    }

    private var removeButton: some View {
        Button { manager.remove(job) } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain).foregroundStyle(.tertiary)
        .help("Remove")
    }

    private func reveal() {
        guard let path = job.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
