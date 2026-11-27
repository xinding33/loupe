import Foundation
import Testing

@testable import LoupeCore

private let base =
  "https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?win_mode=fullscreen&authkey_ver=1&region=os_usa&lang=en&game_biz=hk4e_global&gacha_type=301&page=1&size=5&end_id=0"

private func link(_ key: String) -> String { base + "&authkey=\(key)" }

/// The cache file is binary, with the link between other bytes and other URLs.
private func cache(_ strings: [String]) -> Data {
  var data = Data([0x00, 0xC3, 0xFF])
  for string in strings {
    data += Data(string.utf8)
    data += Data([0x00, 0x9F, 0x22, 0x01])
  }
  return data
}

private func query(_ url: URL) -> [String: String] {
  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
  return Dictionary(items.map { ($0.name, $0.value ?? "") }) { $1 }
}

private func pull(_ id: Int, _ type: String = "301", rank: String = "3") -> [String: String] {
  [
    "uid": "100000001", "gacha_type": type, "item_id": "", "count": "1",
    "time": "2026-11-27 03:49:26", "name": "Item \(id)", "lang": "en-us", "item_type": "Weapon",
    "rank_type": rank, "id": "17640000000000\(String(format: "%05d", id))",
  ]
}

private func response(_ items: [[String: String]], retcode: Int = 0, message: String = "OK")
  -> Data
{
  let body: [String: Any] = [
    "retcode": retcode, "message": message,
    "data": retcode == 0
      ? ["page": "1", "size": "20", "list": items, "region": "os_usa"] : NSNull(),
  ]
  return try! JSONSerialization.data(withJSONObject: body)
}

@Suite struct WishLinkTests {
  @Test func findsTheLinkInsideBinaryCacheData() throws {
    let data = cache([
      "https://sdk.hoyoverse.com/hk4e/announcement/index.html?authkey=other",
      link("abc%2Bdef%2F%3D%3D"),
    ])
    let links = WishLink.all(inCache: data)
    #expect(links.count == 1)
    #expect(links.first?.region == "os_usa")
  }

  @Test func listsDistinctLinksTheLastWrittenFirst() {
    let links = WishLink.all(inCache: cache([link("one"), link("two"), link("one")]))
    #expect(links.map(\.authkey) == ["one", "two"])
  }

  @Test func trustsOnlyHoYoverseAndMiHoYoServers() {
    let path = "/gacha_info/api/getGachaLog?authkey=key"
    #expect(WishLink("https://hk4e-api.mihoyo.com" + path) != nil)
    #expect(WishLink("https://public-operation-hk4e-sg.hoyoverse.com" + path) != nil)
    #expect(WishLink("https://example.com" + path) == nil)
    #expect(WishLink("https://evilhoyoverse.com" + path) == nil)
    #expect(WishLink("https://hoyoverse.com.example.com" + path) == nil)
    #expect(WishLink("http://hk4e-api.mihoyo.com" + path) == nil)
  }

  @Test func countsOneKeyEncodedTwoWaysOnce() {
    let links = WishLink.all(inCache: cache([link("a%2Bb"), link("a%2bb")]))
    #expect(links.count == 1)
  }

  @Test func ignoresLinksWithoutAnAuthkey() {
    #expect(WishLink.all(inCache: cache([base, base + "&authkey="])).isEmpty)
    #expect(WishLink.all(inCache: Data()).isEmpty)
  }

  @Test func pageReplacesPagingAndKeepsTheAuthkeyEncoded() throws {
    let wish = try #require(WishLink(link("abc%2Bdef%2F%3D%3D")))
    let url = wish.page(.standard, endID: "123", size: 20)
    #expect(url.absoluteString.contains("authkey=abc%2Bdef%2F%3D%3D"))
    let items = query(url)
    #expect(items["gacha_type"] == "200")
    #expect(items["end_id"] == "123")
    #expect(items["size"] == "20")
    #expect(items["page"] == "1")
    #expect(items["lang"] == "en")
    #expect(url.absoluteString.components(separatedBy: "gacha_type=").count == 2)
  }
}

@Suite struct WishPageTests {
  @Test func readsPulls() throws {
    let page = try WishPage(json: response([pull(1, "400", rank: "5"), pull(2)]))
    #expect(page.uid == "100000001")
    #expect(page.region == "os_usa")
    #expect(page.lang == "en-us")
    #expect(page.wishes.map(\.gachaType) == ["400", "301"])
    // The second character banner is filed under the first, as UIGF wants.
    #expect(page.wishes.map(\.uigfGachaType) == ["301", "301"])
    #expect(page.wishes.first?.rankType == "5")
  }

  @Test func mapsErrors() {
    #expect(throws: WishError.expired) {
      try WishPage(json: response([], retcode: -101, message: "authkey timeout"))
    }
    #expect(throws: WishError.invalidLink) {
      try WishPage(json: response([], retcode: -100, message: "authkey error"))
    }
    #expect(throws: WishError.tooFrequent) {
      try WishPage(json: response([], retcode: -110, message: "visit too frequently"))
    }
    #expect(throws: WishError.service(code: -1, message: "system error")) {
      try WishPage(json: response([], retcode: -1, message: "system error"))
    }
  }
}

/// A fake history API: each banner's pulls, newest first, served 20 at a time.
private final class FakeAPI: @unchecked Sendable {
  let banners: [String: [[String: String]]]
  let expiredKeys: Set<String>
  /// Serves the first page whatever the cursor, like a server that ignores it.
  var ignoresCursor = false
  private let lock = NSLock()
  private var sent: [URL] = []
  private var tooFrequent: Int

  init(_ banners: [String: [[String: String]]], tooFrequent: Int = 0, expired: Set<String> = []) {
    self.banners = banners
    self.tooFrequent = tooFrequent
    expiredKeys = expired
  }

  var requests: [URL] { lock.withLock { sent } }

  func fetch(_ url: URL) -> Data {
    let limited = lock.withLock {
      sent.append(url)
      defer { tooFrequent = max(0, tooFrequent - 1) }
      return tooFrequent > 0
    }
    let items = query(url)
    if expiredKeys.contains(items["authkey"] ?? "") { return response([], retcode: -101) }
    if limited { return response([], retcode: -110) }
    let all = banners[items["gacha_type"] ?? ""] ?? []
    let end = ignoresCursor ? "0" : items["end_id"] ?? "0"
    let start = end == "0" ? 0 : (all.firstIndex { $0["id"] == end }.map { $0 + 1 } ?? all.count)
    let size = Int(items["size"] ?? "20") ?? 20
    return response(Array(all[start..<min(all.count, start + size)]))
  }

  func download() -> WishDownload {
    WishDownload(fetch: { self.fetch($0) }, pause: { _ in })
  }
}

@Suite struct WishDownloadTests {
  @Test func pagesThroughEveryBanner() async throws {
    let character = (1...45).reversed().map { pull($0) }
    let standard = (100...102).reversed().map { pull($0, "200") }
    let api = FakeAPI(["301": character, "200": standard])
    let wish = try #require(WishLink(link("key")))
    let result = try await api.download().run(wish)
    #expect(result.uid == "100000001")
    #expect(result.region == "os_usa")
    #expect(result.wishes.count == 48)
    #expect(Set(result.wishes.map(\.id)).count == 48)
    // Beginners' and standard take one page each, the character banner three, the rest one each.
    #expect(api.requests.count == 7)
  }

  @Test func stopsAtTheFirstPullItAlreadyHas() async throws {
    let character = (1...45).reversed().map { pull($0) }
    let api = FakeAPI(["301": character])
    let known = Set(character[5...].compactMap { $0["id"] })
    let result = try await api.download().run(try #require(WishLink(link("key"))), known: known)
    #expect(result.wishes.map(\.name) == (41...45).reversed().map { "Item \($0)" })
    let characterRequests = api.requests.filter { query($0)["gacha_type"] == "301" }
    #expect(characterRequests.count == 1)
  }

  @Test func stopsWhenThePageNeverMoves() async throws {
    let api = FakeAPI(["301": (1...20).reversed().map { pull($0) }])
    api.ignoresCursor = true
    await #expect(throws: WishError.stalled) {
      try await api.download().run(try #require(WishLink(link("key"))))
    }
    #expect(api.requests.count < 10)
  }

  @Test func takesTheRegionFromTheResponse() async throws {
    let api = FakeAPI(["200": [pull(1, "200")]])
    let noRegion = try #require(
      WishLink(
        "https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?authkey=key"))
    #expect(noRegion.region == nil)
    #expect(try await api.download().run(noRegion).region == "os_usa")
  }

  @Test func retriesWhenRequestsAreTooFrequent() async throws {
    let api = FakeAPI(["301": [pull(1)]], tooFrequent: 2)
    let result = try await api.download().run(try #require(WishLink(link("key"))))
    #expect(result.wishes.count == 1)
  }

  @Test func triesTheNextLinkWhenOneHasExpired() async throws {
    let api = FakeAPI(["301": [pull(1)]], expired: ["old"])
    let links = [link("old"), link("new")].compactMap(WishLink.init)
    let result = try await api.download().run(links)
    #expect(result.wishes.count == 1)
  }

  @Test func reportsExpiryWhenEveryLinkHasExpired() async throws {
    let api = FakeAPI([:], expired: ["old"])
    await #expect(throws: WishError.expired) {
      try await api.download().run([link("old")].compactMap(WishLink.init))
    }
    await #expect(throws: WishError.noLink) { try await api.download().run([]) }
  }
}

@Suite final class WishHistoryTests {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: folder) }

  func download(_ ids: [Int]) throws -> DownloadedWishes {
    let page = try WishPage(json: response(ids.map { pull($0) }))
    return DownloadedWishes(uid: page.uid, region: "os_usa", lang: page.lang, wishes: page.wishes)
  }

  @Test func addsOnlyNewPullsOldestFirst() throws {
    var history = WishHistory()
    #expect(history.add(try download([3, 2])) == 2)
    #expect(history.add(try download([5, 4, 3])) == 2)
    #expect(history.hk4e.count == 1)
    #expect(history.hk4e[0].timezone == -5)
    #expect(history.hk4e[0].list.map(\.name) == (2...5).map { "Item \($0)" })
    #expect(history.knownIDs.count == 4)
    #expect(history.add(DownloadedWishes()) == 0)
  }

  @Test func sortsLongerIDsAsNewer() {
    let older = Wish(time: "", id: "999")
    let newer = Wish(time: "", id: "1000")
    #expect(Wish.isOlder(older, newer))
    #expect(!Wish.isOlder(newer, older))
  }

  @Test func roundTripsAsUIGF() throws {
    var history = WishHistory()
    history.add(try download([2, 1]))
    let file = folder.appending(path: "wishes.json")
    try history.write(
      to: file, app: "Loupe", version: "1.2.3", exported: Date(timeIntervalSince1970: 1000))
    let read = try WishHistory.read(from: file)
    #expect(read.hk4e == history.hk4e)
    #expect(read.info.exportTimestamp == 1000)
    #expect(read.info.version == "v4.0")
    let json = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let account = try #require((json["hk4e"] as? [[String: Any]])?.first)
    let item = try #require((account["list"] as? [[String: Any]])?.first)
    #expect(item["uigf_gacha_type"] as? String == "301")
    #expect(item["item_id"] as? String == "")
  }

  @Test func readsANumericUID() throws {
    let file = folder.appending(path: "numeric.json")
    try Data(
      """
      {"info": {"export_timestamp": 1, "export_app": "x", "export_app_version": "1",
        "version": "v4.0"},
       "hk4e": [{"uid": 100000001, "timezone": 8, "lang": "en-us", "list": []}]}
      """.utf8
    ).write(to: file)
    #expect(try WishHistory.read(from: file).hk4e.first?.uid == "100000001")
  }

  @Test func refusesAFileItCannotRead() throws {
    let file = folder.appending(path: "broken.json")
    try Data("{".utf8).write(to: file)
    #expect(throws: WishError.self) { try WishHistory.read(from: file) }
  }

  @Test func saveLeavesADamagedHistoryAsItIs() async throws {
    let file = folder.appending(path: "wishes.json")
    let export = folder.appending(path: "export.json")
    let damaged = Data("{\"info\": ".utf8)
    try damaged.write(to: file)
    await #expect(throws: WishError.self) {
      try await WishHistory.save(
        try self.download([1]), to: file, export: export, app: "Loupe", version: "1")
    }
    #expect(try Data(contentsOf: file) == damaged)
    #expect(!FileManager.default.fileExists(atPath: export.path))
  }

  @Test func saveAddsToTheHistoryAsItIsWhenSaving() async throws {
    let file = folder.appending(path: "nested/wishes.json")
    let export = folder.appending(path: "export.json")
    let first = try await WishHistory.save(
      try download([2, 1]), to: file, export: export, app: "Loupe", version: "1")
    #expect(first == WishHistory.Saved(uid: "100000001", added: 2, total: 2))
    // Another download that started before the first was saved still keeps the first's pulls.
    let second = try await WishHistory.save(
      try download([3]), to: file, export: export, app: "Loupe", version: "1")
    #expect(second == WishHistory.Saved(uid: "100000001", added: 1, total: 3))
    #expect(try WishHistory.read(from: file).hk4e == WishHistory.read(from: export).hk4e)
    #expect(try WishHistory.read(from: file).knownIDs.count == 3)
  }

  @Test func timezoneFollowsTheServer() {
    #expect(WishHistory.timezone(region: "os_usa") == -5)
    #expect(WishHistory.timezone(region: "os_euro") == 1)
    #expect(WishHistory.timezone(region: "os_asia") == 8)
    #expect(WishHistory.timezone(region: nil) == 8)
  }
}

extension Wish {
  fileprivate init(time: String, id: String) {
    self.init(gachaType: "200", time: time, name: "", itemType: "", rankType: "3", id: id)
  }
}

@Suite final class WishCacheTests {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let files = FileManager.default

  init() throws { try files.createDirectory(at: folder, withIntermediateDirectories: true) }

  deinit { try? FileManager.default.removeItem(at: folder) }

  func write(_ text: String, to path: String) throws {
    let url = folder.appending(path: path)
    try files.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }

  @Test func readsYaaglsGameFolder() throws {
    try write("/Users/someone/YAAGL Games\n", to: "Yaagl OS/.storage/game_install_dir.neustorage")
    try write("relative", to: "Yaagl/.storage/game_install_dir.neustorage")
    try write("/elsewhere", to: "Other/.storage/game_install_dir.neustorage")
    let folders = WishCache.yaaglGameFolders(support: folder, files: files)
    #expect(folders.map(\.path) == ["/Users/someone/YAAGL Games"])
  }

  @Test func findsTheDataFolderFromTheGameFolderOrItself() throws {
    try write("", to: "game/GenshinImpact_Data/webCaches/2.57.0.0/Cache/Cache_Data/data_2")
    let data = folder.appending(path: "game/GenshinImpact_Data")
    #expect(WishCache.dataFolder(for: folder.appending(path: "game"))?.path == data.path)
    #expect(WishCache.dataFolder(for: data)?.path == data.path)
    #expect(WishCache.dataFolder(for: folder) == nil)
  }

  @Test func picksTheMostRecentlyWrittenCache() throws {
    try write("old", to: "data/webCaches/2.56.0.0/Cache/Cache_Data/data_2")
    try write("new", to: "data/webCaches/2.57.0.0/Cache/Cache_Data/data_2")
    let old = folder.appending(path: "data/webCaches/2.56.0.0/Cache/Cache_Data/data_2")
    try files.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)
    let found = WishCache.cacheFile(in: folder.appending(path: "data"))
    #expect(found?.path.contains("2.57.0.0") == true)
    #expect(WishCache.cacheFile(in: folder) == nil)
  }

  @Test func picksTheMostRecentCacheAcrossGameFolders() throws {
    try write("fresh", to: "new/webCaches/2.57.0.0/Cache/Cache_Data/data_2")
    try write("stale", to: "old/webCaches/2.50.0.0/Cache/Cache_Data/data_2")
    let stale = folder.appending(path: "old/webCaches/2.50.0.0/Cache/Cache_Data/data_2")
    try files.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -86400)], ofItemAtPath: stale.path)
    let found = WishCache.cacheFile(
      in: [folder.appending(path: "old"), folder.appending(path: "new")])
    #expect(found?.path.contains("/new/") == true)
  }
}
