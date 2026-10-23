import Foundation

public struct CardStability {
  public private(set) var signature: String?
  public private(set) var isVerified = false
  private var candidate: String?
  private var verifiedAt: Date?

  public init() {}

  public mutating func observe(_ reading: String?, at time: Date) {
    expire(at: time)
    isVerified = false
    guard let reading else {
      candidate = nil
      return
    }
    if reading != signature { signature = nil }
    if reading == candidate {
      signature = reading
      isVerified = true
      verifiedAt = time
    }
    candidate = reading
  }

  @discardableResult
  public mutating func expire(at time: Date) -> Bool {
    guard let verifiedAt, time.timeIntervalSince(verifiedAt) >= 3 else { return false }
    self = CardStability()
    return true
  }

  public mutating func useManual(_ signature: String) {
    self = CardStability()
    self.signature = signature
    isVerified = true
  }
}
