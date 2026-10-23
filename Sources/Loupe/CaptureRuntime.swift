import Foundation

@MainActor
protocol CaptureConnection: AnyObject {
  func start() async throws
  func stop() async throws
  func invalidate()
}

/// Serializes stream transitions while closing delivery immediately on each request.
@MainActor
final class CaptureRuntime {
  private(set) var generation = UUID()
  private var accepting = false
  private var connection: (any CaptureConnection)?
  private var transition: Task<Void, Never>?
  var ready: (() -> Void)?
  var failed: ((Error) -> Void)?

  func accepts(_ token: UUID) -> Bool { accepting && generation == token }

  func replace(with make: ((UUID) throws -> any CaptureConnection)?) {
    generation = UUID()
    let token = generation
    accepting = make != nil
    connection?.invalidate()
    let previous = transition
    transition = Task {
      await previous?.value
      guard generation == token else { return }
      if let old = connection {
        connection = nil
        do { try await old.stop() } catch {
          connection = old
          guard generation == token else { return }
          accepting = false
          failed?(error)
          return
        }
      }
      guard generation == token, let make else { return }
      do {
        let next = try make(token)
        connection = next
        try await next.start()
        guard accepts(token) else { return }
        ready?()
      } catch {
        guard generation == token else { return }
        accepting = false
        connection?.invalidate()
        if let connection {
          do { try await connection.stop() } catch {
            guard generation == token else { return }
            failed?(error)
            return
          }
        }
        guard generation == token else { return }
        connection = nil
        failed?(error)
      }
    }
  }

  func waitForTransition() async { await transition?.value }
}

/// Only the gate crosses queues; image and OCR state stay on the reader queue.
final class FrameGate: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true

  var isActive: Bool { lock.withLock { active } }
  func close() { lock.withLock { active = false } }
}
