import Foundation
import Security

// Kernel-enforced XPC requirement pins messages to the exact bundled peer executable.
// This works with ad-hoc local builds and avoids trusting a spoofable bundle identifier.
public func signingRequirement(for url: URL) throws -> String {
  var code: SecStaticCode?
  guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
    throw FanError("Cannot inspect bundled peer signature.")
  }
  var info: CFDictionary?
  guard
    SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
      == errSecSuccess,
    let values = info as? [String: Any], let hash = values[kSecCodeInfoUnique as String] as? Data
  else { throw FanError("Bundled peer must be code signed.") }
  return "cdhash H\"\(hash.map { String(format:"%02x",$0) }.joined())\""
}
