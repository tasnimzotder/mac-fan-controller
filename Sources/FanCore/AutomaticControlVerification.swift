import Foundation

/// Conservative read-only proof for removing an unreachable helper. Missing readbacks
/// cannot be treated as release; unsupported unlock keys use authenticated recovery.
public enum AutomaticControlVerification {
  public static func verify(
    readNumber: (String) -> Double?, allowMissingUnlock: Bool = false
  ) throws {
    guard let count = readNumber("FNum"), count.isFinite,
      (0...9).contains(count), count == count.rounded() else {
      throw FanError("Cannot remove helper: fan count is unavailable.")
    }
    let unlock = readNumber("Ftst")
    guard unlock == 0 || (allowMissingUnlock && unlock == nil) else {
      throw FanError("Cannot remove helper: firmware unlock release is unconfirmed.")
    }
    for id in 0..<Int(count) {
      guard let mode = readNumber("F\(id)md") ?? readNumber("F\(id)Md"),
        mode == 0 || mode == 3 else {
        throw FanError("Cannot remove helper: fan \(id + 1) automatic mode is unconfirmed.")
      }
      // macOS can populate Tg itself after release. Mode and Ftst identify ownership;
      // zero is not a stable automatic target. Still require valid target readback.
      guard let maximum = readNumber("F\(id)Mx"), maximum.isFinite,
        maximum > 0, maximum <= 15000,
        let target = readNumber("F\(id)Tg"), target.isFinite,
        target >= 0, target <= maximum else {
        throw FanError("Cannot remove helper: fan \(id + 1) target release is unconfirmed.")
      }
    }
  }
}
