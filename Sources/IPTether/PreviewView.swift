import IPTetherCore
import SwiftUI

/// Shows what a sync would change before anything is written. First-run setup ends here.
struct PreviewView: View {
    static let windowID = "preview"
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview Changes")
                    .font(.title2.weight(.semibold))
                Text("IPTether checks every firewall that allows SSH and lists what it would change. Nothing is written until you apply.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = model.preview {
                summary(for: preview)
                ScrollView {
                    Text(preview.output.isEmpty ? "No output." : preview.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 220)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            } else if model.isRunning {
                ProgressView("Checking your firewalls…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("This takes a minute or two with many firewalls.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            HStack {
                Button(model.preview == nil ? "Run Preview" : "Run Again") {
                    Task { await model.runPreview() }
                }
                .disabled(model.isRunning)
                Spacer()
                if let preview = model.preview, !preview.isEngineError {
                    Button("Apply Once") { model.applyPreview(turnOnAutomatic: false) }
                        .disabled(model.isRunning)
                    if !model.config.schedule.automatic {
                        Button("Apply and Turn On Automatic Updates") {
                            model.applyPreview(turnOnAutomatic: true)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isRunning)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .task {
            // on first run, start the dry run straight away; it only reads the clouds
            if model.needsSetup && model.preview == nil {
                await model.runPreview()
            }
        }
    }

    @ViewBuilder
    private func summary(for preview: SyncOutcome) -> some View {
        let counts = PreviewSummary(output: preview.output)
        switch preview.result {
        case .error:
            Label(preview.summary, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        default:
            HStack(spacing: 20) {
                stat(counts.adds, "to add")
                stat(counts.updates, "to update")
                stat(counts.removes, "to remove")
                stat(counts.production, "production, skipped")
                if preview.result == .failures {
                    Label("Some firewalls couldn't be read", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(value)").font(.title3.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
