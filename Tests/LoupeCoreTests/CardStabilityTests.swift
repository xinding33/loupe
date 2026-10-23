import Foundation
import LoupeCore
import Testing

private let start = Date(timeIntervalSince1970: 1_000)

@Test func missedFrameKeepsLastResultButRequiresTwoReadingsBeforeSaving() {
  var state = CardStability()
  state.observe("plume +0", at: start)
  #expect(state.signature == nil)
  #expect(!state.isVerified)
  state.observe("plume +0", at: start.addingTimeInterval(0.5))
  #expect(state.isVerified)
  state.observe(nil, at: start.addingTimeInterval(1))
  #expect(state.signature == "plume +0")
  #expect(!state.isVerified)
  state.observe("plume +0", at: start.addingTimeInterval(1.5))
  #expect(state.signature == "plume +0")
  #expect(!state.isVerified)
  state.observe("plume +0", at: start.addingTimeInterval(2))
  #expect(state.signature == "plume +0")
  #expect(state.isVerified)
}

@Test func repeatedFailuresDoNotExtendLastVerifiedResultsLifetime() {
  var state = CardStability()
  state.observe("plume +0", at: start)
  state.observe("plume +0", at: start.addingTimeInterval(0.5))
  state.observe(nil, at: start.addingTimeInterval(1))
  state.observe(nil, at: start.addingTimeInterval(3))
  #expect(state.signature == "plume +0")
  let beforeDeadline = state.expire(at: start.addingTimeInterval(3.49))
  #expect(!beforeDeadline)
  let atDeadline = state.expire(at: start.addingTimeInterval(3.5))
  #expect(atDeadline)
  #expect(state.signature == nil)
  #expect(!state.isVerified)
  state.observe("plume +0", at: start.addingTimeInterval(4))
  #expect(!state.isVerified)
}

@Test func changedArtifactImmediatelyHidesOldResultUntilVerified() {
  var state = CardStability()
  state.observe("plume +0", at: start)
  state.observe("plume +0", at: start.addingTimeInterval(0.5))
  state.observe("plume +4", at: start.addingTimeInterval(1))
  #expect(state.signature == nil)
  #expect(!state.isVerified)
  state.observe("plume +4", at: start.addingTimeInterval(1.5))
  #expect(state.signature == "plume +4")
  #expect(state.isVerified)
}

@Test func frozenCaptureExpiresButManualCardDoesNot() {
  var state = CardStability()
  state.observe("plume +0", at: start)
  state.observe("plume +0", at: start)
  let expired = state.expire(at: start.addingTimeInterval(3))
  #expect(expired)
  #expect(state.signature == nil)
  state.useManual("flower +20")
  let manualExpired = state.expire(at: start.addingTimeInterval(10))
  #expect(!manualExpired)
  #expect(state.signature == "flower +20")
  #expect(state.isVerified)
}
