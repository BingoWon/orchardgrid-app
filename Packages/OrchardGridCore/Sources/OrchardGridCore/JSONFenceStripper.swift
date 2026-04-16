import Foundation

// MARK: - JSONFenceStripper
//
// Removes a surrounding Markdown code fence from JSON content. When a
// chat completion is requested with `response_format: { "type":
// "json_object" }`, the OpenAI spec requires the assistant message to
// be directly parseable as JSON. Apple's on-device FoundationModels
// often emits a fenced block ```json\n{...}\n``` despite explicit
// instructions; we post-process the output to deliver raw JSON.
//
// Lives in `OrchardGridCore` so the on-device LLMProcessor (app),
// the LAN APIServer, and any future cloud-side consumer can share
// one implementation.
//
// Behaviour:
// - Input wrapped in ```` ``` ```` or ```` ```json ```` (any case)
//   on the opening line and ```` ``` ```` on a closing line:
//   return the inner content trimmed of surrounding whitespace.
// - Other fence flavours (```python ...```, ```yaml ...```): leave
//   the content untouched so we don't corrupt non-JSON code blocks.
// - No fence at all: return the input verbatim (still a no-op trim
//   would change semantics for callers that care about whitespace).

public enum JSONFenceStripper {
  public static func strip(_ content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
      return content
    }
    guard let firstNewline = trimmed.firstIndex(of: "\n") else {
      return content
    }
    let fenceTag = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)..<firstNewline]
      .trimmingCharacters(in: .whitespaces)
      .lowercased()
    // Only strip when the fence is JSON-flavored or untagged.
    guard fenceTag.isEmpty || fenceTag == "json" else {
      return content
    }
    let afterOpen = trimmed.index(after: firstNewline)
    var inner = String(trimmed[afterOpen...])
    if let closingRange = inner.range(of: "```", options: .backwards) {
      inner = String(inner[..<closingRange.lowerBound])
    }
    return inner.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
