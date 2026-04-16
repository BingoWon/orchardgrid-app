import Testing

@testable import OrchardGridCore

@Suite("JSONFenceStripper")
struct JSONFenceStripperTests {

  @Test("strips ```json fenced block")
  func jsonTaggedFence() {
    let input = "```json\n{\"a\":1}\n```"
    #expect(JSONFenceStripper.strip(input) == "{\"a\":1}")
  }

  @Test("strips untagged ``` fenced block")
  func untaggedFence() {
    let input = "```\n{\"a\":1}\n```"
    #expect(JSONFenceStripper.strip(input) == "{\"a\":1}")
  }

  @Test("strips fence ignoring case (```JSON)")
  func uppercaseTag() {
    let input = "```JSON\n{\"a\":1}\n```"
    #expect(JSONFenceStripper.strip(input) == "{\"a\":1}")
  }

  @Test("preserves leading/trailing whitespace around fence")
  func surroundingWhitespace() {
    let input = "  \n```json\n{\"a\":1}\n```  \n"
    #expect(JSONFenceStripper.strip(input) == "{\"a\":1}")
  }

  @Test("leaves non-JSON fences untouched (```python)")
  func nonJsonFence() {
    let input = "```python\nprint('hi')\n```"
    #expect(JSONFenceStripper.strip(input) == input)
  }

  @Test("returns content unchanged when there is no fence")
  func noFence() {
    let input = "{\"a\":1}"
    #expect(JSONFenceStripper.strip(input) == input)
  }

  @Test("returns content unchanged for opening fence without newline")
  func malformedSingleLine() {
    let input = "```{\"a\":1}```"
    #expect(JSONFenceStripper.strip(input) == input)
  }

  @Test("preserves inner newlines and indentation")
  func multilineJsonInside() {
    let input = "```json\n{\n  \"a\": 1,\n  \"b\": 2\n}\n```"
    #expect(JSONFenceStripper.strip(input) == "{\n  \"a\": 1,\n  \"b\": 2\n}")
  }
}
