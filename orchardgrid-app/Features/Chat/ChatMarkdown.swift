import SwiftUI

// MARK: - Public View

struct ChatMarkdownView: View {
  let content: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(MarkdownParser.parse(content).enumerated()), id: \.offset) { _, block in
        blockView(for: block)
      }
    }
  }

  @ViewBuilder
  private func blockView(for block: MarkdownBlock) -> some View {
    switch block {
    case .paragraph(let text):
      inlineMarkdown(text)

    case .heading(let level, let text):
      headingView(level: level, text: text)
        .padding(.top, level == 1 ? 6 : 4)

    case .codeBlock(let language, let code):
      CodeBlockView(language: language, code: code)

    case .list(let items, let ordered):
      listView(items: items, ordered: ordered)

    case .blockquote(let text):
      blockquoteView(text: text)

    case .divider:
      Divider().padding(.vertical, 4)
    }
  }

  // MARK: - Inline Markdown

  private func inlineMarkdown(_ text: String) -> some View {
    Group {
      if let attributed = try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      ) {
        Text(attributed)
          .font(.body)
      } else {
        Text(text)
          .font(.body)
      }
    }
    .textSelection(.enabled)
  }

  // MARK: - Heading

  private func headingView(level: Int, text: String) -> some View {
    Group {
      if let attributed = try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      ) {
        Text(attributed)
          .font(headingFont(for: level))
          .fontWeight(.semibold)
      } else {
        Text(text)
          .font(headingFont(for: level))
          .fontWeight(.semibold)
      }
    }
  }

  private func headingFont(for level: Int) -> Font {
    switch level {
    case 1: .title2
    case 2: .title3
    case 3: .headline
    default: .subheadline
    }
  }

  // MARK: - List

  private func listView(items: [(String, Int)], ordered: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        let (text, indent) = item
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          let marker = ordered ? "\(index + 1)." : "•"
          Text(marker)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: ordered ? 20 : 12, alignment: .trailing)

          if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
          ) {
            Text(attributed)
              .font(.body)
          } else {
            Text(text)
              .font(.body)
          }
        }
        .padding(.leading, CGFloat(indent) * 16)
        .textSelection(.enabled)
      }
    }
  }

  // MARK: - Blockquote

  private func blockquoteView(text: String) -> some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(.blue.opacity(0.5))
        .frame(width: 3)

      if let attributed = try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      ) {
        Text(attributed)
          .font(.body)
          .foregroundStyle(.secondary)
      } else {
        Text(text)
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
    .textSelection(.enabled)
  }
}

// MARK: - Code Block View

private struct CodeBlockView: View {
  let language: String?
  let code: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      ScrollView(.horizontal, showsIndicators: false) {
        Text(code)
          .font(.system(.callout, design: .monospaced))
          .textSelection(.enabled)
          .padding(12)
      }
    }
    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
    )
  }

  private var header: some View {
    HStack {
      if let language, !language.isEmpty {
        Text(language)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)
      }

      Spacer()

      CopyButton(text: code)
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 2)
  }

}

// MARK: - Block Types

private enum MarkdownBlock {
  case paragraph(String)
  case heading(Int, String)
  case codeBlock(String?, String)
  case list([(String, Int)], Bool)
  case blockquote(String)
  case divider
}

// MARK: - Parser

private enum MarkdownParser {
  static func parse(_ input: String) -> [MarkdownBlock] {
    let lines = input.components(separatedBy: "\n")
    var blocks: [MarkdownBlock] = []
    var i = 0

    while i < lines.count {
      let line = lines[i]

      // Code block
      if line.hasPrefix("```") {
        let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        i += 1
        while i < lines.count, !lines[i].hasPrefix("```") {
          codeLines.append(lines[i])
          i += 1
        }
        if i < lines.count { i += 1 }
        blocks.append(
          .codeBlock(
            language.isEmpty ? nil : language,
            codeLines.joined(separator: "\n")
          ))
        continue
      }

      // Divider
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed == "---" || trimmed == "***" || trimmed == "___" {
        blocks.append(.divider)
        i += 1
        continue
      }

      // Heading
      if let heading = parseHeading(line) {
        blocks.append(.heading(heading.0, heading.1))
        i += 1
        continue
      }

      // Blockquote
      if trimmed.hasPrefix("> ") {
        var quoteLines: [String] = []
        while i < lines.count {
          let ql = lines[i].trimmingCharacters(in: .whitespaces)
          if ql.hasPrefix("> ") {
            quoteLines.append(String(ql.dropFirst(2)))
          } else if ql.hasPrefix(">") {
            quoteLines.append(String(ql.dropFirst(1)))
          } else {
            break
          }
          i += 1
        }
        blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
        continue
      }

      // Unordered list
      if isUnorderedListItem(trimmed) {
        var items: [(String, Int)] = []
        while i < lines.count {
          let ll = lines[i]
          let indent = ll.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
          let lt = ll.trimmingCharacters(in: .whitespaces)
          if isUnorderedListItem(lt) {
            let text = String(lt.drop(while: { $0 == "-" || $0 == "*" || $0 == " " }))
            items.append((text, indent))
          } else if lt.isEmpty, !items.isEmpty {
            // empty line in list, skip
          } else {
            break
          }
          i += 1
        }
        if !items.isEmpty {
          blocks.append(.list(items, false))
        }
        continue
      }

      // Ordered list
      if isOrderedListItem(trimmed) {
        var items: [(String, Int)] = []
        while i < lines.count {
          let ll = lines[i]
          let indent = ll.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
          let lt = ll.trimmingCharacters(in: .whitespaces)
          if isOrderedListItem(lt) {
            let text = String(lt.drop(while: { $0.isNumber || $0 == "." || $0 == " " }))
            items.append((text, indent))
          } else if lt.isEmpty, !items.isEmpty {
            // empty line in list, skip
          } else {
            break
          }
          i += 1
        }
        if !items.isEmpty {
          blocks.append(.list(items, true))
        }
        continue
      }

      // Empty line = paragraph break
      if trimmed.isEmpty {
        i += 1
        continue
      }

      // Regular text — accumulate into paragraph
      var paraLines: [String] = []
      while i < lines.count {
        let pl = lines[i]
        let pt = pl.trimmingCharacters(in: .whitespaces)
        if pt.isEmpty || pt.hasPrefix("```") || pt.hasPrefix("# ") || pt.hasPrefix("## ")
          || pt.hasPrefix("### ") || pt.hasPrefix("#### ") || pt.hasPrefix("> ")
          || pt == "---" || pt == "***" || pt == "___"
          || isUnorderedListItem(pt) || isOrderedListItem(pt)
        {
          break
        }
        paraLines.append(pl)
        i += 1
      }
      if !paraLines.isEmpty {
        blocks.append(.paragraph(paraLines.joined(separator: "\n")))
      }
    }

    return blocks
  }

  // MARK: - Helpers

  private static func parseHeading(_ line: String) -> (Int, String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    var level = 0
    for ch in trimmed {
      if ch == "#" { level += 1 } else { break }
    }
    guard level >= 1, level <= 6, trimmed.count > level,
      trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == " "
    else { return nil }
    let text = String(trimmed.dropFirst(level + 1))
    return (level, text)
  }

  private static func isUnorderedListItem(_ line: String) -> Bool {
    line.hasPrefix("- ") || line.hasPrefix("* ")
  }

  private static func isOrderedListItem(_ line: String) -> Bool {
    guard let dotIndex = line.firstIndex(of: ".") else { return false }
    let prefix = line[line.startIndex..<dotIndex]
    guard prefix.allSatisfy(\.isNumber), !prefix.isEmpty else { return false }
    let afterDot = line.index(after: dotIndex)
    return afterDot < line.endIndex && line[afterDot] == " "
  }
}
