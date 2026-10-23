import AppKit
import SwiftUI

struct DiagnosticControls: View {
  @ObservedObject var flow: DiagnosticReportFlow
  let report: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Buffer diagnostic crops", isOn: Binding(get: { flow.optedIn }, set: flow.setOptedIn))
        .toggleStyle(.switch).controlSize(.small)
      Text("Off at each launch. Memory only, up to 10 s / 24 MiB. Inventory evidence is partial.")
        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if flow.optedIn {
        Text(
          "Retained \(flow.coverage.count) samples · \(flow.coverage.duration.formatted(.number.precision(.fractionLength(1)))) s · \(Int64(flow.coverage.imageBytes).formatted(.byteCount(style: .memory)))"
        )
        .font(.caption2).monospacedDigit()
      }
      if let issue = flow.coverage.issue {
        Text(issue).font(.caption2).foregroundStyle(Theme.attention)
      }
      Button("Report issue", systemImage: "exclamationmark.bubble", action: report)
        .disabled(!flow.canRequest)
      if case .freezing = flow.phase { ProgressView("Freezing evidence...").controlSize(.small) }
      if !flow.saveStatus.isEmpty { Text(flow.saveStatus).font(.caption2).textSelection(.enabled) }
    }
  }
}

struct DiagnosticPresentation: View {
  @ObservedObject var flow: DiagnosticReportFlow

  var body: some View {
    Color.clear.frame(width: 0, height: 0)
      .sheet(isPresented: Binding(get: { flow.isPresented }, set: { if !$0 { flow.close() } })) {
        switch flow.phase {
        case .preview(let report): DiagnosticReportView(flow: flow, report: report)
        case .unavailable(let reason):
          VStack(alignment: .leading, spacing: 16) {
            Text("No report evidence").font(.title2.bold())
            Text(reason)
            Text("Reporting does not enable capture or start recording.").foregroundStyle(
              .secondary)
            Button("Close") { flow.close() }.keyboardShortcut(.cancelAction)
          }.padding(24).frame(width: 520)
        default: EmptyView()
        }
      }
  }
}

struct DiagnosticReportView: View {
  @ObservedObject var flow: DiagnosticReportFlow
  let report: DiagnosticReport
  @State private var issue = DiagnosticAnnotation.Issue.wrongRead
  @State private var expected = ""
  @State private var notes = ""
  @State private var sampleID: UUID?
  @State private var metadata = "Preparing metadata preview..."
  @State private var metadataReady = false
  @State private var images: [UUID: [CGImage]] = [:]
  @State private var error: String?

  var body: some View {
    let start = report.snapshot.samples.first?.metadata.time ?? 0
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text("Report issue").font(.title2.bold())
        Spacer()
        Chip(text: "\(report.snapshot.samples.count) samples")
        Chip(
          text:
            "\(report.snapshot.retainedDuration.formatted(.number.precision(.fractionLength(1)))) s"
        )
        Chip(
          text:
            "\(report.snapshot.evictedSamples) evicted · \(report.snapshot.oversizedSamples) oversized"
        )
        Chip(text: "Collection paused", systemImage: "pause.fill")
      }
      Label(DiagnosticReport.previewWarning, systemImage: "lock.shield")
        .font(.callout).foregroundStyle(Theme.attention)
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.attention.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
        GridRow {
          Text("Issue").foregroundStyle(.secondary)
          Picker("Issue", selection: $issue) {
            Text("Wrong reading").tag(DiagnosticAnnotation.Issue.wrongRead)
            Text("Flicker").tag(DiagnosticAnnotation.Issue.flicker)
            Text("Recommendation").tag(DiagnosticAnnotation.Issue.recommendation)
            Text("Placement").tag(DiagnosticAnnotation.Issue.placement)
          }
          .pickerStyle(.segmented).labelsHidden()
        }
        GridRow {
          Text("Applies to").foregroundStyle(.secondary)
          Picker("Expected reading applies to", selection: $sampleID) {
            Text("Whole report").tag(nil as UUID?)
            ForEach(Array(report.snapshot.samples.enumerated()), id: \.element.metadata.id) {
              index, sample in
              Text(label(index, sample, start: start)).tag(Optional(sample.metadata.id))
            }
          }
          .labelsHidden()
        }
        GridRow {
          Text("Expected").foregroundStyle(.secondary)
          TextField("Expected reading (annotation only)", text: $expected, axis: .vertical)
            .textFieldStyle(.roundedBorder)
        }
        GridRow {
          Text("Notes").foregroundStyle(.secondary)
          TextField("Notes", text: $notes, axis: .vertical).textFieldStyle(.roundedBorder)
        }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(report.snapshot.samples.enumerated()), id: \.element.metadata.id) {
            index, sample in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(label(index, sample, start: start)).font(.caption.bold())
                Spacer()
                Text(sample.metadata.id.uuidString).font(.caption2.monospaced())
                  .foregroundStyle(.tertiary).textSelection(.enabled)
              }
              if sample.inputs.isEmpty {
                Text("Metadata only. No safe artifact crop was retained.").font(.caption)
                  .foregroundStyle(.secondary)
              }
              ForEach(Array(sample.inputs.enumerated()), id: \.offset) { inputIndex, input in
                Text(
                  "\(input.metadata.kind.rawValue): \(input.metadata.isExactOCRInput ? "exact OCR input" : "partial crop, not the full OCR input")"
                )
                .font(.caption2).foregroundStyle(.secondary)
                if let image = images[sample.metadata.id]?[inputIndex] {
                  Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .frame(maxWidth: 680, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Retained \(input.metadata.kind.rawValue) crop")
                }
              }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
          }
          Text("Replay limits").font(.headline)
          ForEach(report.context.replayLimitations, id: \.self) {
            Label($0, systemImage: "info.circle").font(.caption).labelStyle(BulletLabelStyle())
          }
          Text("All included metadata").font(.headline)
          Text(metadata).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Cancel") { flow.close() }.keyboardShortcut(.cancelAction)
        Spacer()
        Text("Saved locally. Nothing is uploaded.").font(.caption).foregroundStyle(.secondary)
        if flow.isSaving { ProgressView().controlSize(.small) }
        Button("Save local report...") { chooseDestination() }
          .buttonStyle(.borderedProminent)
          .disabled(flow.isSaving || !metadataReady)
      }
    }
    .padding(24).frame(width: 760, height: 760)
    .tint(Theme.accent)
    .task(id: report.id) {
      do {
        metadata = try await Task.detached(priority: .utility) { try report.previewMetadata() }
          .value
        for sample in report.snapshot.samples {
          images[sample.metadata.id] = try sample.inputs.map { try $0.pixels.makeImage() }
        }
        metadataReady = true
      } catch { self.error = error.localizedDescription }
    }
  }

  private func label(_ index: Int, _ sample: DiagnosticSample, start: TimeInterval) -> String {
    let offset = (sample.metadata.time - start).formatted(.number.precision(.fractionLength(1)))
    return "#\(index + 1) · \(sample.metadata.mode.rawValue.capitalized) · +\(offset) s"
  }

  private func chooseDestination() {
    let panel = NSSavePanel()
    panel.title = "Save local diagnostic report folder"
    panel.nameFieldStringValue = "Loupe-report-\(report.id.uuidString)"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    let annotation = DiagnosticAnnotation(
      issue: issue, notes: notes, expectedReading: expected, sampleID: sampleID)
    Task {
      do {
        let saved = try await flow.save(to: destination, annotation: annotation)
        NSWorkspace.shared.activateFileViewerSelecting([saved])
      } catch { self.error = error.localizedDescription }
    }
  }
}
