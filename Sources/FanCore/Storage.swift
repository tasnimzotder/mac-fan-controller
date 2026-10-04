import CSQLite
import Foundation

public final class Storage {
  private var db: OpaquePointer?
  public let path: String
  public init(path: String) throws {
    self.path = path
    try FileManager.default.createDirectory(
      atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
      withIntermediateDirectories: true)
    guard
      sqlite3_open_v2(
        path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK
    else { throw FanError("Could not open SQLite database.") }
    sqlite3_busy_timeout(db, 3000)
    try execute(
      "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; CREATE TABLE IF NOT EXISTS settings(id INTEGER PRIMARY KEY CHECK(id=1),json TEXT NOT NULL); CREATE TABLE IF NOT EXISTS samples(id INTEGER PRIMARY KEY, timestamp REAL NOT NULL, temperature REAL, rpm REAL NOT NULL); CREATE INDEX IF NOT EXISTS samples_time ON samples(timestamp); PRAGMA user_version=1;"
    )
  }
  deinit { sqlite3_close(db) }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
  }
  private func error() -> FanError {
    FanError(db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite unavailable")
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw error()
    }
    return statement
  }
  public func settings() throws -> Settings {
    let s = try prepare("SELECT json FROM settings WHERE id=1")
    defer { sqlite3_finalize(s) }
    let result = sqlite3_step(s)
    if result == SQLITE_DONE { return Settings() }
    guard result == SQLITE_ROW, let value = sqlite3_column_text(s, 0) else { throw error() }
    return try JSONDecoder().decode(Settings.self, from: Data(String(cString: value).utf8))
  }
  public func save(_ settings: Settings) throws {
    let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
    let s = try prepare(
      "INSERT INTO settings(id,json) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json")
    defer { sqlite3_finalize(s) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(s, 1, json, -1, transient)
    guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
  }
  public func record(_ snapshot: Snapshot, retentionDays: Int) throws {
    let s = try prepare("INSERT INTO samples(timestamp,temperature,rpm) VALUES(?,?,?)")
    defer { sqlite3_finalize(s) }
    sqlite3_bind_double(s, 1, snapshot.date.timeIntervalSince1970)
    if let t = snapshot.hottest { sqlite3_bind_double(s, 2, t) } else { sqlite3_bind_null(s, 2) }
    sqlite3_bind_double(s, 3, snapshot.fans.map(\.rpm).max() ?? 0)
    guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
    let cleanup = try prepare("DELETE FROM samples WHERE timestamp < ?")
    defer { sqlite3_finalize(cleanup) }
    sqlite3_bind_double(
      cleanup, 1,
      snapshot.date.addingTimeInterval(-Double(max(1, min(30, retentionDays))) * 86400)
        .timeIntervalSince1970)
    guard sqlite3_step(cleanup) == SQLITE_DONE else { throw error() }
  }
  public func history(since: Date) throws -> [HistoryPoint] {
    // Aggregate in SQLite: at most about 720 buckets regardless of retention window.
    let bucket = max(60, ceil(max(0, Date().timeIntervalSince(since)) / 720 / 60) * 60)
    let s = try prepare(
      "SELECT MIN(id),CAST(timestamp/? AS INTEGER)*?,MAX(temperature),MAX(rpm) FROM samples WHERE timestamp>=? GROUP BY CAST(timestamp/? AS INTEGER) ORDER BY 2"
    )
    defer { sqlite3_finalize(s) }
    sqlite3_bind_double(s, 1, bucket)
    sqlite3_bind_double(s, 2, bucket)
    sqlite3_bind_double(s, 3, since.timeIntervalSince1970)
    sqlite3_bind_double(s, 4, bucket)
    var points: [HistoryPoint] = []
    while true {
      let result = sqlite3_step(s)
      if result == SQLITE_DONE { break }
      guard result == SQLITE_ROW else { throw error() }
      points.append(
        HistoryPoint(
          id: sqlite3_column_int64(s, 0),
          date: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
          temperature: sqlite3_column_type(s, 2) == SQLITE_NULL ? nil : sqlite3_column_double(s, 2),
          rpm: sqlite3_column_double(s, 3)))
    }
    return points
  }
}
