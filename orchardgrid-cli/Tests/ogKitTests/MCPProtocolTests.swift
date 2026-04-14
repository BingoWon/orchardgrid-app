import Foundation
import Testing

@testable import ogKit

@Suite("MCP wire protocol")
struct MCPProtocolTests {

  // MARK: - Request framing

  @Test("initializeRequest is well-formed JSON-RPC 2.0")
  func initializeRequest() throws {
    let json = MCPProtocol.initializeRequest(id: 1)
    let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    #expect(obj["jsonrpc"] as? String == "2.0")
    #expect(obj["id"] as? Int == 1)
    #expect(obj["method"] as? String == "initialize")
    let params = obj["params"] as! [String: Any]
    #expect(params["protocolVersion"] as? String == MCPProtocol.protocolVersion)
  }

  @Test("initialized notification carries no id")
  func initializedNotification() throws {
    let json = MCPProtocol.initializedNotification()
    let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    #expect(obj["id"] == nil)
    #expect(obj["method"] as? String == "notifications/initialized")
  }

  @Test("toolsCallRequest parses argument JSON back into a dict")
  func toolsCallRequest() throws {
    let json = MCPProtocol.toolsCallRequest(id: 5, name: "add", argumentsJSON: "{\"a\":1,\"b\":2}")
    let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    let params = obj["params"] as! [String: Any]
    let args = params["arguments"] as! [String: Any]
    #expect(args["a"] as? Int == 1)
    #expect(args["b"] as? Int == 2)
  }

  @Test("malformed argument JSON falls back to empty arguments")
  func toolsCallRequestBadJSON() throws {
    let json = MCPProtocol.toolsCallRequest(id: 5, name: "add", argumentsJSON: "not-json")
    let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    let args = (obj["params"] as! [String: Any])["arguments"] as! [String: Any]
    #expect(args.isEmpty)
  }

  // MARK: - Response parsing

  @Test("parseInitializeResponse extracts serverInfo")
  func parseInit() throws {
    let info = try MCPProtocol.parseInitializeResponse(
      #"{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"calc","version":"0.1"}}}"#
    )
    #expect(info.name == "calc")
    #expect(info.version == "0.1")
  }

  @Test("parseInitializeResponse rejects missing serverInfo")
  func parseInitMissing() {
    #expect(throws: MCPError.self) {
      try MCPProtocol.parseInitializeResponse(#"{"result":{}}"#)
    }
  }

  @Test("parseToolsListResponse reads name / description / schema")
  func parseTools() throws {
    let raw = """
      {"result":{"tools":[
        {"name":"add","description":"sum","inputSchema":{"type":"object","properties":{}}}
      ]}}
      """
    let tools = try MCPProtocol.parseToolsListResponse(raw)
    #expect(tools.count == 1)
    #expect(tools[0].name == "add")
    #expect(tools[0].description == "sum")
    #expect(tools[0].inputSchema.contains("\"type\""))
  }

  @Test("parseToolCallResponse extracts text content")
  func parseCallOK() throws {
    let raw = #"{"result":{"content":[{"type":"text","text":"42"}]}}"#
    let res = try MCPProtocol.parseToolCallResponse(raw)
    #expect(res.text == "42")
    #expect(res.isError == false)
  }

  @Test("parseToolCallResponse surfaces JSON-RPC errors as isError")
  func parseCallError() throws {
    let raw = #"{"error":{"code":-32601,"message":"unknown tool"}}"#
    let res = try MCPProtocol.parseToolCallResponse(raw)
    #expect(res.text == "unknown tool")
    #expect(res.isError == true)
  }

  @Test("parseToolCallResponse honors explicit isError flag")
  func parseCallIsError() throws {
    let raw = #"{"result":{"content":[{"type":"text","text":"boom"}],"isError":true}}"#
    let res = try MCPProtocol.parseToolCallResponse(raw)
    #expect(res.isError == true)
  }
}

@Suite("MCP argument parsing")
struct MCPArgumentTests {

  @Test("--mcp appends repeatedly")
  func mcpRepeatable() throws {
    let args = try parseArguments(
      ["--mcp", "/tmp/a.py", "--mcp", "/tmp/b.py", "hi"], env: [:])
    #expect(args.mcpPaths == ["/tmp/a.py", "/tmp/b.py"])
    #expect(args.prompt == "hi")
  }

  @Test("--mcp-timeout parses positive Int")
  func mcpTimeout() throws {
    let args = try parseArguments(["--mcp-timeout", "30", "hi"], env: [:])
    #expect(args.mcpTimeoutSeconds == 30)
  }

  @Test("--mcp-timeout rejects zero / negative")
  func mcpTimeoutInvalid() {
    #expect(throws: CLIError.self) {
      _ = try parseArguments(["--mcp-timeout", "0"], env: [:])
    }
  }

  @Test("`og mcp list <path>` → .mcpList with paths")
  func mcpList() throws {
    let args = try parseArguments(["mcp", "list", "/tmp/calc.py"], env: [:])
    #expect(args.mode == .mcpList)
    #expect(args.mcpPaths == ["/tmp/calc.py"])
  }

  @Test("`og mcp list` with no path is rejected")
  func mcpListMissing() {
    #expect(throws: CLIError.self) {
      _ = try parseArguments(["mcp", "list"], env: [:])
    }
  }

  @Test("`og mcp` with no verb is rejected with a clean message")
  func mcpMissingVerb() {
    do {
      _ = try parseArguments(["mcp"], env: [:])
      Issue.record("expected throw")
    } catch let err as CLIError {
      let msg = err.description
      #expect(msg.contains("mcp verb"))
      #expect(!msg.hasSuffix(" "))
    } catch { Issue.record("wrong error: \(error)") }
  }

  @Test("`og mcp unknown` is rejected without trailing space")
  func mcpUnknownVerb() {
    do {
      _ = try parseArguments(["mcp", "wiggle"], env: [:])
      Issue.record("expected throw")
    } catch let err as CLIError {
      #expect(err.description == "unknown subcommand: mcp wiggle")
    } catch { Issue.record("wrong error: \(error)") }
  }

  @Test("--mcp combined with --host is rejected at parse time")
  func mcpAndHostMutuallyExclusive() {
    do {
      _ = try parseArguments(["--mcp", "/tmp/s.py", "--host", "http://x", "hi"], env: [:])
      Issue.record("expected throw")
    } catch let err as CLIError {
      #expect(err.description.contains("--mcp"))
      #expect(err.description.contains("on-device"))
    } catch { Issue.record("wrong error: \(error)") }
  }

  @Test("--mcp is allowed with `og mcp list` even if a host is in ORCHARDGRID_HOST")
  func mcpListIgnoresHostEnv() throws {
    let args = try parseArguments(
      ["mcp", "list", "/tmp/s.py"],
      env: ["ORCHARDGRID_HOST": "http://x"])
    #expect(args.mode == .mcpList)
  }
}
