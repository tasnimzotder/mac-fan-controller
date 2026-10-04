import Foundation

public let helperLabel = "com.tasnimzotder.mac-fan-controller.helper"
public enum ControlMode: String, Codable, CaseIterable {
  case automatic, performance, balanced, quiet, manual
  public var title: String { self == .automatic ? "Apple automatic" : rawValue.capitalized }
}
public struct Fan: Codable, Identifiable, Equatable {
  public var id: Int
  public var rpm: Double
  public var minimum: Double
  public var maximum: Double
  public var target: Double
  public var mode: Int
  public init(
    id: Int, rpm: Double, minimum: Double, maximum: Double, target: Double = 0, mode: Int = 0
  ) {
    self.id = id
    self.rpm = rpm
    self.minimum = minimum
    self.maximum = maximum
    self.target = target
    self.mode = mode
  }
  public var controllable: Bool {
    minimum.isFinite && maximum.isFinite && minimum > 0 && maximum > minimum && maximum < 15000
  }
}
public struct Sensor: Codable, Identifiable {
  public var id: String
  public var temperature: Double
  public init(id: String, temperature: Double) {
    self.id = id
    self.temperature = temperature
  }
}
public struct Snapshot: Codable {
  public var date: Date
  public var fans: [Fan]
  public var sensors: [Sensor]
  public var thermalState: Int
  public var completeSensorReadings: Bool
  public var hottest: Double? { sensors.map(\.temperature).max() }
  public init(
    date: Date = Date(), fans: [Fan], sensors: [Sensor], thermalState: Int = 0,
    completeSensorReadings: Bool = true
  ) {
    self.date = date
    self.fans = fans
    self.sensors = sensors
    self.thermalState = thermalState
    self.completeSensorReadings = completeSensorReadings
  }
}
public struct Settings: Codable, Equatable {
  public var showTemperature = true
  public var showRPM = true
  public var showBothFans = false
  public var syncFans = true
  public var manualFractions: [Double] = [0.5, 0.5]
  public var historyDays = 7
  // Mode is deliberately not persisted: every launch returns to Apple automatic.
  public init() {}
}
public struct HistoryPoint: Identifiable {
  public var id: Int64
  public var date: Date
  public var temperature: Double?
  public var rpm: Double
}
public struct HelperRequest: Codable {
  public var mode: ControlMode
  public var fractions: [Double]
  public var statusOnly: Bool?
  public init(mode: ControlMode, fractions: [Double] = [], statusOnly: Bool? = nil) {
    self.mode = mode
    self.fractions = fractions
    self.statusOnly = statusOnly
  }
}
public struct HelperReply: Codable {
  public var mode: ControlMode
  public var error: String?
  public init(mode: ControlMode, error: String? = nil) {
    self.mode = mode
    self.error = error
  }
}
@objc public protocol FanHelperProtocol {
  func command(_ data: Data, reply: @escaping (Data) -> Void)
}
public struct FanError: LocalizedError {
  public var message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}
