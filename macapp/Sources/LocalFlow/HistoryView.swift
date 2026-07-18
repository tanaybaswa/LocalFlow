import AppKit
import SwiftUI

struct HistoryView: View {
    @Bindable var controller: DictationController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if controller.transcripts.entries.isEmpty {
                ContentUnavailableView(
                    "No transcripts yet",
                    systemImage: "waveform",
                    description: Text("Hold Right ⌘ anywhere to dictate. Transcripts appear here.")
                )
            } else {
                List {
                    ForEach(controller.transcripts.entries) { entry in
                        TranscriptRow(entry: entry) {
                            controller.transcripts.delete(entry.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LocalFlow")
                    .font(.headline)
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            statusBadge
            Button("Clear") {
                controller.transcripts.clear()
            }
            .disabled(controller.transcripts.entries.isEmpty)
        }
        .padding(16)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch controller.state {
            case .ready: return (controller.enabled ? "Ready" : "Paused", .green)
            case .recording: return ("Recording", .red)
            case .transcribing: return ("Transcribing", .orange)
            case .startingSidecar: return ("Loading", .orange)
            case .error: return ("Error", .red)
            case .idle: return ("Idle", .secondary)
            }
        }()
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
            HStack {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let target = entry.targetApplication {
                    Text("• \(target)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let method = entry.pasteMethod {
                    Text("• \(method)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let succeeded = entry.pasteSucceeded {
                    Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(succeeded ? .green : .orange)
                        .help(succeeded ? "Paste delivered" : "Paste failed; transcript left on clipboard")
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
                .buttonStyle(.borderless)
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
