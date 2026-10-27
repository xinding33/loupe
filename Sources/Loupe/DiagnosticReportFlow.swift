import Foundation
import SwiftUI

@MainActor
final class DiagnosticReportFlow: ObservableObject {
  enum Phase {
    case idle
    case freezing(UUID)
    case unavailable(String)
    case preview(DiagnosticReport)
  }
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var optedIn = false
  @Published private(set) var isSaving = false
  @Published private(set) var coverage = DiagnosticCoverage(
    count: 0, duration: 0, imageBytes: 0, issue: nil)
  @Published var saveStatus = ""
  private(set) var sessionID: UUID?
  private let setCollection: (Bool) -> Void
  private let exporter = DiagnosticExporter()
  var present: (() -> Void)?
  /// Called when the user flips the buffer toggle, so the choice outlasts the launch.
  var didChangeOptIn: ((Bool) -> Void)?

  init(setCollection: @escaping (Bool) -> Void) { self.setCollection = setCollection }

  var isPresented: Bool {
    switch phase {
    case .unavailable, .preview: true
    case .idle, .freezing: false
    }
  }
  var canRequest: Bool {
    guard !isSaving else { return false }
    if case .idle = phase { return true }
    return false
  }

  func setOptedIn(_ value: Bool) {
    optedIn = value
    didChangeOptIn?(value)
    reset()
  }

  func beginSession(_ id: UUID?) {
    sessionID = id
    reset()
  }

  private func reset() {
    phase = .idle
    coverage = DiagnosticCoverage(count: 0, duration: 0, imageBytes: 0, issue: nil)
    setCollection(optedIn && sessionID != nil && !isSaving)
  }

  func updateCoverage(_ value: DiagnosticCoverage, session: UUID) {
    guard session == sessionID, optedIn else { return }
    guard case .idle = phase else { return }
    coverage = value
  }

  @discardableResult
  func request(
    context: DiagnosticReportContext,
    freeze: @escaping @MainActor () async throws -> DiagnosticSnapshot
  ) -> Task<Void, Never>? {
    guard canRequest else { return nil }
    guard optedIn, let sessionID else {
      phase = .unavailable(
        "No buffered evidence. Enable the diagnostic buffer, share the game window, and reproduce the issue before reporting. You can instead explicitly record 40 full-window frames from the main window; those may include UID and chat."
      )
      present?()
      return nil
    }
    let requestID = UUID()
    phase = .freezing(requestID)
    return Task {
      guard case .freezing(let pending) = phase, pending == requestID,
        self.sessionID == sessionID, optedIn
      else { return }
      do {
        let snapshot = try await freeze()
        guard case .freezing(let pending) = phase, pending == requestID,
          self.sessionID == sessionID,
          snapshot.sessionID == sessionID, optedIn
        else { return }
        if snapshot.samples.isEmpty {
          phase = .unavailable(
            "No recent evidence remains. Close this preview, reproduce the issue with buffering enabled, then report again."
          )
        } else {
          phase = .preview(
            DiagnosticReport(
              id: UUID(), context: context,
              annotation: DiagnosticAnnotation(
                issue: .wrongRead, notes: "", expectedReading: "", sampleID: nil),
              snapshot: snapshot))
        }
        present?()
      } catch {
        guard case .freezing(let pending) = phase, pending == requestID, self.sessionID == sessionID
        else { return }
        phase = .unavailable(error.localizedDescription)
        present?()
      }
    }
  }

  func close() {
    phase = .idle
    coverage = DiagnosticCoverage(count: 0, duration: 0, imageBytes: 0, issue: nil)
    setCollection(optedIn && sessionID != nil && !isSaving)
  }

  func save(to url: URL, annotation: DiagnosticAnnotation) async throws -> URL {
    guard !isSaving, case .preview(let report) = phase else {
      saveStatus = "Report save failed: no available preview, or a save is already in progress."
      throw DiagnosticError.invalid("no report preview is available")
    }
    let annotated = DiagnosticReport(
      id: report.id, context: report.context, annotation: annotation, snapshot: report.snapshot)
    isSaving = true
    saveStatus = "Saving local report..."
    defer {
      isSaving = false
      if case .idle = phase { setCollection(optedIn && sessionID != nil) }
    }
    do {
      let saved = try await exporter.save(annotated, to: url)
      saveStatus = "Saved locally: \(saved.path)"
      if case .preview(let current) = phase, current.id == report.id { phase = .idle }
      return saved
    } catch {
      saveStatus = "Report save failed: \(error.localizedDescription)"
      throw error
    }
  }
}
