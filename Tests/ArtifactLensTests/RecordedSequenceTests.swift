import ArtifactCore
import Foundation
import ImageIO
import Testing

@testable import ArtifactLens

@Test(.enabled(if: ProcessInfo.processInfo.environment["ARTIFACT_LENS_FIXTURES"] != nil))
func recordedEnhanceSequenceReadsWithoutWrongCards() throws {
  let path = try #require(ProcessInfo.processInfo.environment["ARTIFACT_LENS_FIXTURES"])
  let folder = URL(fileURLWithPath: path, isDirectory: true)
  let text = try String(contentsOf: folder.appending(path: "expected.txt"), encoding: .utf8)
  let previous = try CardParser.parse(text, fiveStarsConfirmed: true)
  let name = try #require(text.components(separatedBy: .newlines).first)
  let files = try FileManager.default.contentsOfDirectory(
    at: folder, includingPropertiesForKeys: nil
  )
  .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  #expect(files.count >= 20)
  var successes = 0
  var reader = LiveCardOCR()
  var stability = CardStability()
  var acquired = false
  var cleared = 0
  for (index, file) in files.enumerated() {
    let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
    let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    do {
      let reading = try reader.read(frame, at: Double(index) * 0.5)
      let actual = try reading.resolveEnhancement(previous: previous, pieceName: name)
      #expect(actual.signature == previous.signature)
      stability.observe(actual.signature, at: Date(timeIntervalSince1970: Double(index) * 0.5))
      successes += 1
    } catch {
      stability.observe(nil, at: Date(timeIntervalSince1970: Double(index) * 0.5))
      print("\(file.lastPathComponent): \(error.localizedDescription)")
    }
    if acquired && stability.signature == nil { cleared += 1 }
    acquired = acquired || stability.isVerified
  }
  print("Recognized \(successes)/\(files.count) recorded frames")
  #expect(Double(successes) / Double(files.count) >= 0.95)
  #expect(acquired)
  #expect(cleared == 0)
}
