import Foundation

/// The wish banners the history API pages through. The character banner also returns the second
/// character banner's pulls (gacha type 400).
public enum WishBanner: String, CaseIterable, Sendable {
  case beginners = "100"
  case standard = "200"
  case character = "301"
  case weapon = "302"
  case chronicled = "500"
}

public enum WishError: LocalizedError, Equatable {
  case noLink
  case expired
  case invalidLink
  case tooFrequent
  case service(code: Int, message: String)
  case httpStatus(Int)
  case unreadableHistory(String)
  case stalled

  public var errorDescription: String? {
    switch self {
    case .noLink:
      return
        "The game hasn't saved a wish history link. Open Wish, then History, in the game and try again."
    case .expired:
      return
        "The game's wish history link has expired. Open Wish, then History, in the game again and try again."
    case .invalidLink:
      return
        "HoYoverse didn't accept the game's wish history link. Open Wish, then History, in the game again and try again."
    case .tooFrequent: return "HoYoverse is limiting requests. Wait a minute and try again."
    case .service(let code, let message): return "HoYoverse returned error \(code): \(message)"
    case .httpStatus(let status): return "HoYoverse responded with HTTP status \(status)."
    case .unreadableHistory(let reason):
      return "Loupe's saved wish history can't be read, so it was left as it is. \(reason)"
    case .stalled:
      return "HoYoverse kept sending the same page of wish history, so the download stopped."
    }
  }
}

/// The link the game opens for Wish > History. It carries an authkey that lasts about a day.
/// The authkey is a credential: never log it or write it anywhere.
public struct WishLink: Equatable, Sendable {
  let components: URLComponents

  /// Only HoYoverse's and miHoYo's own servers get the authkey.
  static func isTrusted(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
    return ["hoyoverse.com", "mihoyo.com"].contains { host == $0 || host.hasSuffix(".\($0)") }
  }

  public init?(_ string: String) {
    guard let components = URLComponents(string: string), let url = components.url,
      Self.isTrusted(url), components.path.hasSuffix("/getGachaLog"),
      let items = components.percentEncodedQueryItems,
      items.contains(where: { $0.name == "authkey" && $0.value?.isEmpty == false })
    else { return nil }
    self.components = components
  }

  /// Decoded, so the same key encoded two ways counts once.
  var authkey: String? {
    components.queryItems?.first { $0.name == "authkey" }?.value
  }
  /// The game server, like os_usa, which sets the history's time zone.
  public var region: String? {
    components.queryItems?.first { $0.name == "region" }?.value
  }

  /// Every distinct link in the game's web cache file, the one written last first. The cache isn't
  /// strictly in order, so callers try the next when one has expired.
  public static func all(inCache data: Data) -> [WishLink] {
    // The links are ASCII. Other bytes decode as replacement characters, which end a link.
    let text = String(decoding: data, as: Unicode.ASCII.self)
    var links: [WishLink] = []
    var position = text.startIndex
    while let start = text.range(of: "https://", range: position..<text.endIndex) {
      let end = text[start.lowerBound...].firstIndex { !isURLCharacter($0) } ?? text.endIndex
      position = end > start.upperBound ? end : start.upperBound
      guard let link = WishLink(String(text[start.lowerBound..<end])) else { continue }
      links.removeAll { $0.authkey == link.authkey }
      links.append(link)
    }
    return links.reversed()
  }

  private static func isURLCharacter(_ character: Character) -> Bool {
    guard let ascii = character.asciiValue, ascii > 0x20, ascii < 0x7F else { return false }
    return !"\"<>\\^`{|}".contains(character)
  }

  /// One page of `banner`, newest first, of the pulls older than `endID` ("0" for the newest).
  public func page(_ banner: WishBanner, endID: String, size: Int = 20) -> URL {
    var components = components
    let replaced: [String: String] = [
      "gacha_type": banner.rawValue, "page": "1", "size": String(size), "end_id": endID,
    ]
    var items = (components.percentEncodedQueryItems ?? []).filter { replaced[$0.name] == nil }
    for name in ["gacha_type", "page", "size", "end_id"] {
      items.append(URLQueryItem(name: name, value: replaced[name]))
    }
    // The authkey stays percent-encoded as the game wrote it, so its + and / survive.
    components.percentEncodedQueryItems = items
    return components.url!
  }
}

/// One pull, in UIGF v4's field names and string values.
public struct Wish: Codable, Equatable, Sendable {
  public var uigfGachaType: String
  public var gachaType: String
  public var itemID: String
  public var count: String
  public var time: String
  public var name: String
  public var itemType: String
  public var rankType: String
  public var id: String

  public init(
    gachaType: String, itemID: String = "", count: String = "1", time: String, name: String,
    itemType: String, rankType: String, id: String
  ) {
    uigfGachaType = gachaType == "400" ? "301" : gachaType
    self.gachaType = gachaType
    self.itemID = itemID
    self.count = count
    self.time = time
    self.name = name
    self.itemType = itemType
    self.rankType = rankType
    self.id = id
  }

  enum CodingKeys: String, CodingKey {
    case uigfGachaType = "uigf_gacha_type"
    case gachaType = "gacha_type"
    case itemID = "item_id"
    case count, time, name
    case itemType = "item_type"
    case rankType = "rank_type"
    case id
  }

  init(id: String) {
    self.init(gachaType: "", time: "", name: "", itemType: "", rankType: "", id: id)
  }

  /// Pull IDs grow with time but are too long to compare as text unless the lengths match.
  static func isOlder(_ a: Wish, _ b: Wish) -> Bool {
    a.id.count != b.id.count ? a.id.count < b.id.count : a.id < b.id
  }
}

/// One response from the history API.
public struct WishPage: Sendable {
  public let uid: String?
  public let lang: String?
  public let region: String?
  public let wishes: [Wish]

  public init(json data: Data) throws {
    struct Response: Decodable {
      struct Page: Decodable {
        let list: [Item]
        let region: String?
      }
      struct Item: Decodable {
        let uid: String
        let gachaType: String
        let itemId: String?
        let count: String?
        let time: String
        let name: String
        let lang: String?
        let itemType: String
        let rankType: String
        let id: String
      }
      let retcode: Int
      let message: String?
      let data: Page?
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(Response.self, from: data)
    switch response.retcode {
    case 0: break
    case -101: throw WishError.expired
    case -100: throw WishError.invalidLink
    case -110: throw WishError.tooFrequent
    default: throw WishError.service(code: response.retcode, message: response.message ?? "")
    }
    let items = response.data?.list ?? []
    uid = items.first?.uid
    lang = items.first?.lang
    region = response.data?.region
    wishes = items.map {
      Wish(
        gachaType: $0.gachaType, itemID: $0.itemId ?? "", count: $0.count ?? "1", time: $0.time,
        name: $0.name, itemType: $0.itemType, rankType: $0.rankType, id: $0.id)
    }
  }
}

/// Pulls fetched by one download, for one account.
public struct DownloadedWishes: Equatable, Sendable {
  public var uid: String?
  public var region: String?
  public var lang: String?
  /// Newest first within each banner.
  public var wishes: [Wish] = []
}

/// Pages through every banner. `fetch` and `pause` are injectable so paging can be tested.
public struct WishDownload: Sendable {
  public var fetch: @Sendable (URL) async throws -> Data
  public var pause: @Sendable (Duration) async throws -> Void
  /// Between requests, so a full download stays under the API's rate limit.
  public var interval: Duration = .milliseconds(350)

  public init(
    fetch: @escaping @Sendable (URL) async throws -> Data = WishDownload.fetchLive,
    pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.fetch = fetch
    self.pause = pause
  }

  /// The request carries the authkey, so nothing is cached and redirects aren't followed.
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }()

  private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? { nil }
  }

  @Sendable public static func fetchLive(_ url: URL) async throws -> Data {
    guard WishLink.isTrusted(url) else { throw WishError.invalidLink }
    let (data, response) = try await session.data(
      for: URLRequest(url: url), delegate: NoRedirects())
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw WishError.httpStatus(http.statusCode)
    }
    return data
  }

  /// Tries each link in turn until one hasn't expired, then downloads with it.
  public func run(
    _ links: [WishLink], known: Set<String> = [],
    progress: @Sendable (Int) -> Void = { _ in }
  ) async throws -> DownloadedWishes {
    guard !links.isEmpty else { throw WishError.noLink }
    var lastError = WishError.noLink
    for link in links {
      do {
        return try await run(link, known: known, progress: progress)
      } catch let error as WishError where error == .expired || error == .invalidLink {
        lastError = error
      }
    }
    throw lastError
  }

  /// Every pull newer than the first one in `known`, banner by banner.
  public func run(
    _ link: WishLink, known: Set<String> = [], progress: @Sendable (Int) -> Void = { _ in }
  ) async throws -> DownloadedWishes {
    let size = 20  // The most the API returns at once.
    var result = DownloadedWishes(region: link.region)
    var first = true
    for banner in WishBanner.allCases {
      var endID = "0"
      while true {
        if !first { try await pause(interval) }
        first = false
        let page = try await self.page(link.page(banner, endID: endID, size: size))
        result.uid = result.uid ?? page.uid
        result.lang = result.lang ?? page.lang
        result.region = page.region ?? result.region
        let fresh = page.wishes.prefix { !known.contains($0.id) }
        result.wishes += fresh
        progress(result.wishes.count)
        // A short page is the last one.
        guard fresh.count == size, let last = page.wishes.last else { break }
        guard endID == "0" || Wish.isOlder(last, Wish(id: endID)) else { throw WishError.stalled }
        endID = last.id
      }
    }
    return result
  }

  /// Retries a few times when the API says requests are too frequent.
  private func page(_ url: URL) async throws -> WishPage {
    for attempt in 1...5 {
      do {
        return try WishPage(json: try await fetch(url))
      } catch WishError.tooFrequent where attempt < 5 {
        try await pause(.seconds(attempt * 2))
      }
    }
    throw WishError.tooFrequent
  }
}

/// Every pull Loupe has downloaded, as a UIGF v4 file. HoYoverse returns only recent pulls, so
/// the file is what holds the older ones.
public struct WishHistory: Codable, Equatable, Sendable {
  public struct Info: Codable, Equatable, Sendable {
    public var exportTimestamp: Int
    public var exportApp: String
    public var exportAppVersion: String
    public var version: String

    enum CodingKeys: String, CodingKey {
      case exportTimestamp = "export_timestamp"
      case exportApp = "export_app"
      case exportAppVersion = "export_app_version"
      case version
    }
  }

  public struct Account: Codable, Equatable, Sendable {
    public var uid: String
    public var timezone: Int
    public var lang: String
    /// Oldest first.
    public var list: [Wish]

    public init(uid: String, timezone: Int, lang: String, list: [Wish]) {
      self.uid = uid
      self.timezone = timezone
      self.lang = lang
      self.list = list
    }

    // UIGF allows the UID as a number or a string.
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let number = try? container.decode(Int.self, forKey: .uid) {
        uid = String(number)
      } else {
        uid = try container.decode(String.self, forKey: .uid)
      }
      timezone = try container.decode(Int.self, forKey: .timezone)
      lang = try container.decode(String.self, forKey: .lang)
      list = try container.decode([Wish].self, forKey: .list)
    }
  }

  public var info: Info
  public var hk4e: [Account]

  public init(app: String = "Loupe", version: String = "0.0.0") {
    info = Info(exportTimestamp: 0, exportApp: app, exportAppVersion: version, version: "v4.0")
    hk4e = []
  }

  public var knownIDs: Set<String> { Set(hk4e.flatMap { $0.list.map(\.id) }) }

  /// The server's UTC offset, which UIGF records because pull times are in server time.
  public static func timezone(region: String?) -> Int {
    switch region {
    case "os_usa": return -5
    case "os_euro": return 1
    default: return 8
    }
  }

  /// Adds the pulls it doesn't have yet and returns how many that was.
  @discardableResult
  public mutating func add(_ download: DownloadedWishes) -> Int {
    guard let uid = download.uid, !download.wishes.isEmpty else { return 0 }
    if !hk4e.contains(where: { $0.uid == uid }) {
      hk4e.append(
        Account(
          uid: uid, timezone: Self.timezone(region: download.region),
          lang: download.lang ?? "en-us", list: []))
    }
    let index = hk4e.firstIndex { $0.uid == uid }!
    var seen = Set(hk4e[index].list.map(\.id))
    let new = download.wishes.filter { seen.insert($0.id).inserted }
    hk4e[index].list = (hk4e[index].list + new).sorted(by: Wish.isOlder)
    return new.count
  }

  public static func read(from url: URL) throws -> WishHistory {
    do {
      return try JSONDecoder().decode(WishHistory.self, from: Data(contentsOf: url))
    } catch {
      throw WishError.unreadableHistory(error.localizedDescription)
    }
  }

  /// What `save` did.
  public struct Saved: Equatable, Sendable {
    public var uid: String?
    public var added: Int
    public var total: Int
  }

  /// Adds `download` to the history at `file`, read again now so a change since the download
  /// started isn't lost, and writes the result there and to `export`. A history that exists but
  /// can't be read is left untouched and nothing is written.
  public static func save(
    _ download: DownloadedWishes, to file: URL, export: URL, app: String, version: String,
    files: FileManager = .default
  ) async throws -> Saved {
    var history = files.fileExists(atPath: file.path) ? try read(from: file) : WishHistory()
    let added = history.add(download)
    try files.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try history.write(to: file, app: app, version: version)
    if export != file { try history.write(to: export, app: app, version: version) }
    let account = history.hk4e.first { $0.uid == download.uid }
    return Saved(uid: download.uid, added: added, total: account?.list.count ?? 0)
  }

  /// Writes the file with `exported` as its export time.
  public func write(to url: URL, app: String, version: String, exported: Date = .now) throws {
    var history = self
    history.info = Info(
      exportTimestamp: Int(exported.timeIntervalSince1970), exportApp: app,
      exportAppVersion: version, version: "v4.0")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(history).write(to: url, options: .atomic)
  }
}

/// Where the game keeps the wish history link on a Mac.
public enum WishCache {
  /// Game folders saved by Yaagl, the Wine launcher, from each of its editions' settings.
  public static func yaaglGameFolders(
    support: URL = .applicationSupportDirectory, files: FileManager = .default
  ) -> [URL] {
    let editions =
      (try? files.contentsOfDirectory(atPath: support.path))?.filter { $0.hasPrefix("Yaagl") }
      ?? []
    return editions.sorted().compactMap { edition in
      let setting = support.appending(path: "\(edition)/.storage/game_install_dir.neustorage")
      guard let text = try? String(contentsOf: setting, encoding: .utf8) else { return nil }
      let path = text.trimmingCharacters(in: .whitespacesAndNewlines.union(["\""]))
      return path.hasPrefix("/") ? URL(filePath: path, directoryHint: .isDirectory) : nil
    }
  }

  /// The game's data folder for `folder`, which can be the game folder or the data folder itself.
  public static func dataFolder(for folder: URL, files: FileManager = .default) -> URL? {
    let candidates = [
      folder, folder.appending(path: "GenshinImpact_Data"), folder.appending(path: "YuanShen_Data"),
    ]
    return candidates.first {
      files.fileExists(atPath: $0.appending(path: "webCaches").path)
    }
  }

  /// The most recently written cache file across `dataFolders`, since a stale install could
  /// otherwise hide a fresh link.
  public static func cacheFile(in dataFolders: [URL], files: FileManager = .default) -> URL? {
    dataFolders.compactMap { cacheFile(in: $0, files: files) }
      .max { modified($0, files) ?? .distantPast < modified($1, files) ?? .distantPast }
  }

  /// The links in `cache`, read off the main thread since the file can be large.
  public static func links(in cache: URL) async throws -> [WishLink] {
    WishLink.all(inCache: try Data(contentsOf: cache))
  }

  private static func modified(_ url: URL, _ files: FileManager) -> Date? {
    try? files.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
  }

  /// The cache file that holds the link: the most recently written one, since each game version
  /// gets its own folder.
  public static func cacheFile(in dataFolder: URL, files: FileManager = .default) -> URL? {
    let caches = dataFolder.appending(path: "webCaches")
    let versions = (try? files.contentsOfDirectory(atPath: caches.path)) ?? []
    let candidates = ([""] + versions).map {
      caches.appending(path: $0).appending(path: "Cache/Cache_Data/data_2")
    }
    return
      candidates
      .compactMap { url in modified(url, files).map { (url, $0) } }
      .max { $0.1 < $1.1 }?.0
  }
}
