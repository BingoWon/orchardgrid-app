import Foundation
import Testing

@testable import ogKit

@Suite("Login flow URL building")
struct LoginFlowTests {

  @Test("composes /cli/login with all required query params")
  func buildLoginURL() throws {
    let base = URL(string: "https://orchardgrid.com")!
    let url = LoginFlow.buildLoginURL(
      base: base, port: 54321, state: "abc123", deviceLabel: "Binus-Mac")

    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    #expect(components.host == "orchardgrid.com")
    #expect(components.path == "/cli/login")

    let items = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(items["redirect_uri"] == "http://127.0.0.1:54321/cb")
    #expect(items["state"] == "abc123")
    #expect(items["device_label"] == "Binus-Mac")
  }

  @Test("works against a local dev host")
  func buildForLocalDev() {
    let base = URL(string: "http://localhost:4399")!
    let url = LoginFlow.buildLoginURL(
      base: base, port: 8765, state: "s", deviceLabel: "x")
    #expect(
      url.absoluteString.hasPrefix("http://localhost:4399/cli/login?"))
  }

  @Test("randomToken length matches byte count (hex encoded)")
  func randomTokenLength() {
    let token = LoginFlow.randomToken(16)
    #expect(token.count == 32)  // 16 bytes → 32 hex chars
    // Hex-only check
    let charset = CharacterSet(charactersIn: "0123456789abcdef")
    #expect(token.unicodeScalars.allSatisfy { charset.contains($0) })
  }

  @Test("randomToken values are different across calls")
  func randomTokenEntropy() {
    let a = LoginFlow.randomToken(16)
    let b = LoginFlow.randomToken(16)
    #expect(a != b)
  }
}
