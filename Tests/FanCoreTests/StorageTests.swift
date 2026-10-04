import XCTest

@testable import FanCore

final class StorageTests: XCTestCase {
  private func temporary(_ body: (String) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appendingPathComponent("history.sqlite3").path)
  }
  func testSettingsPersistAcrossConnectionsWithoutPersistingControlMode() throws {
    try temporary { path in
      var settings = Settings()
      settings.showBothFans = true
      settings.syncFans = false
      settings.manualFractions = [0.2, 0.8]
      try Storage(path: path).save(settings)
      XCTAssertEqual(try Storage(path: path).settings(), settings)
      let encoded = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
      XCTAssertFalse(encoded.contains("mode"))
    }
  }
  func testRetentionAndMinutePeakAggregation() throws {
    try temporary { path in
      let db = try Storage(path: path)
      let minute = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
      let old = Snapshot(date: minute.addingTimeInterval(-9 * 86400), fans: [], sensors: [])
      try db.record(old, retentionDays: 30)
      for (offset, t, rpm) in [(1.0, 55.0, 2000.0), (20.0, 65.0, 3200.0)] {
        try db.record(
          Snapshot(
            date: minute.addingTimeInterval(offset),
            fans: [Fan(id: 0, rpm: rpm, minimum: 1350, maximum: 5349)],
            sensors: [Sensor(id: "CPU", temperature: t)]), retentionDays: 7)
      }
      let history = try db.history(since: Date.distantPast)
      XCTAssertEqual(history.count, 1)
      XCTAssertEqual(history[0].temperature, 65)
      XCTAssertEqual(history[0].rpm, 3200)
    }
  }
  func testMissingTemperatureIsStoredAsNullRatherThanZero() throws {
    try temporary { path in
      let db = try Storage(path: path)
      try db.record(Snapshot(fans: [], sensors: []), retentionDays: 7)
      let points = try db.history(since: Date.distantPast)
      XCTAssertNil(points.first?.temperature)
      XCTAssertEqual(points.first?.rpm, 0)
    }
  }
}
