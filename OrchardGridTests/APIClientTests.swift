import Foundation
import Testing

@testable import OrchardGrid_Dev

@Suite(.serialized)
struct APIClientTests {
  private static let baseURL = URL(string: "https://api.example.com/api")!

  private func makeClient(
    token: String? = "test-token",
    handler: @escaping MockURLProtocol.Handler
  ) -> APIClient {
    MockURLProtocol.handler = handler
    return APIClient(
      baseURL: Self.baseURL,
      session: .mock,
      tokenProvider: { token }
    )
  }

  // MARK: - Happy path

  @Test func getDecodesSuccessfulResponse() async throws {
    struct Payload: Decodable, Equatable { let name: String }

    let client = makeClient { request in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/api/hello")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
      return (
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        Data(#"{"name":"ok"}"#.utf8)
      )
    }

    let result: Payload = try await client.get("/hello")
    #expect(result == Payload(name: "ok"))
  }

  // MARK: - HTTP error with server message

  @Test func httpErrorExposesServerMessage() async throws {
    let client = makeClient { request in
      (
        HTTPURLResponse(
          url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
        Data(#"{"error":"Forbidden"}"#.utf8)
      )
    }

    do {
      let _: [String] = try await client.get("/thing")
      Issue.record("Expected APIError.http to be thrown")
    } catch let error as APIError {
      guard case .http(let status, let message) = error else {
        Issue.record("Expected .http, got \(error)")
        return
      }
      #expect(status == 403)
      #expect(message == "Forbidden")
    }
  }

  // MARK: - Missing auth

  @Test func missingTokenProducesLocalError() async throws {
    let client = makeClient(token: nil) { _ in
      Issue.record("Network must not be called when auth token is missing")
      return (HTTPURLResponse(), Data())
    }

    do {
      let _: [String] = try await client.get("/anything")
      Issue.record("Expected APIError.local to be thrown")
    } catch let error as APIError {
      guard case .local = error else {
        Issue.record("Expected .local, got \(error)")
        return
      }
    }
  }

  // MARK: - POST body + headers

  @Test func postAttachesContentTypeAndBody() async throws {
    struct Body: Encodable { let name: String }
    struct Response: Decodable { let id: String }

    let client = makeClient { request in
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")

      let body = request.httpBody ?? request.httpBodyData()
      let decoded = try #require(try? JSONDecoder().decode([String: String].self, from: body))
      #expect(decoded == ["name": "widget"])

      return (
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        Data(#"{"id":"abc"}"#.utf8)
      )
    }

    let response: Response = try await client.post("/things", body: Body(name: "widget"))
    #expect(response.id == "abc")
  }

  // MARK: - Transport failure

  @Test func transportErrorIsClassified() async throws {
    let client = makeClient { _ in
      throw URLError(.notConnectedToInternet)
    }

    do {
      let _: [String] = try await client.get("/x")
      Issue.record("Expected APIError.transport to be thrown")
    } catch let error as APIError {
      guard case .transport(let urlError) = error else {
        Issue.record("Expected .transport, got \(error)")
        return
      }
      #expect(urlError.code == .notConnectedToInternet)
    }
  }
}

/// URLRequest's `httpBody` is stripped when a URLProtocol subclass sees the request
/// (the body is moved to `httpBodyStream`). This reads the stream into Data.
extension URLRequest {
  fileprivate func httpBodyData() -> Data {
    guard let stream = httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
