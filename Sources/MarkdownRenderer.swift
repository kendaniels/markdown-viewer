import Foundation

enum MarkdownRenderer {
    static let placeholderHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="color-scheme" content="light dark">
      <style>\(baseCSS)</style>
    </head>
    <body>
      <p class="placeholder">Open a Markdown file to view it.</p>
    </body>
    </html>
    """

    static func render(_ markdown: String) throws -> String {
        var parser = MarkdownParser(markdown: markdown)
        let bodyHTML = parser.renderDocument()

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="color-scheme" content="light dark">
          <style>\(baseCSS)</style>
        </head>
        <body>
          \(bodyHTML)
        </body>
        </html>
        """
    }

    static let baseCSS = """
    :root {
      color-scheme: light dark;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      line-height: 1.55;
    }
    body {
      margin: 0 auto;
      max-width: 860px;
      padding: 28px;
      color: #1f2328;
      background: #ffffff;
      font-size: 16px;
      word-wrap: break-word;
    }
    p, ul, ol, pre, blockquote, table {
      margin: 0 0 1em;
    }
    h1, h2, h3, h4, h5, h6 {
      line-height: 1.2;
      margin: 1.4em 0 0.55em;
      font-weight: 700;
    }
    body > :first-child {
      margin-top: 0;
    }
    h1 { font-size: 2em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.25em; }
    ul, ol {
      padding-left: 1.6em;
    }
    li + li {
      margin-top: 0.35em;
    }
    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.92em;
      color: #1f2328;
      background: #f6f8fa;
      padding: 0.12em 0.3em;
      border-radius: 6px;
    }
    pre {
      padding: 14px 16px;
      overflow-x: auto;
      border-radius: 10px;
      background: #f6f8fa;
    }
    pre code {
      color: inherit;
      padding: 0;
      background: transparent;
      border-radius: 0;
    }
    mark {
      color: #1f2328;
      background: #fff3bf;
      padding: 0.08em 0.22em;
      border-radius: 4px;
    }
    blockquote {
      margin-left: 0;
      padding-left: 1em;
      color: #59636e;
      border-left: 4px solid #d0d7de;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    table th, table td {
      border: 1px solid #d0d7de;
      padding: 8px 10px;
      text-align: left;
      vertical-align: top;
    }
    table thead {
      background: #f6f8fa;
    }
    img {
      max-width: 100%;
      height: auto;
    }
    a {
      color: #0969da;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    hr {
      border: 0;
      border-top: 1px solid #d0d7de;
      margin: 1.5em 0;
    }
    .callout {
      margin: 0 0 1em;
      padding: 12px 14px;
      border: 1px solid #d0d7de;
      border-radius: 10px;
      background: #f6f8fa;
    }
    .callout-title {
      font-weight: 700;
      margin-bottom: 0.5em;
      text-transform: capitalize;
    }
    .placeholder {
      color: #6b7280;
    }
    @media (prefers-color-scheme: dark) {
      body {
        color: #e6edf3;
        background: #0d1117;
      }
      code {
        color: #f3f4f6;
        background: #273244;
      }
      pre {
        background: #161b22;
      }
      blockquote {
        color: #9da7b3;
        border-left-color: #3d444d;
      }
      table th, table td {
        border-color: #30363d;
      }
      table thead {
        background: #161b22;
      }
      .callout {
        background: #111827;
        border-color: #374151;
      }
      mark {
        color: #fff7d6;
        background: #5b4a12;
      }
      a {
        color: #58a6ff;
      }
      .placeholder {
        color: #9ca3af;
      }
    }
    """
}

private struct MarkdownParser {
    private let lines: [String]
    private var index = 0

    init(markdown: String) {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        lines = normalized.components(separatedBy: "\n")
    }

    mutating func renderDocument() -> String {
        var blocks: [String] = []

        while index < lines.count {
            if isBlank(lines[index]) {
                index += 1
                continue
            }

            if let block = parseCodeBlock() ??
                parseHeading() ??
                parseHorizontalRule() ??
                parseTable() ??
                parseCalloutOrQuote() ??
                parseUnorderedList() ??
                parseOrderedList() ??
                parseParagraph() {
                blocks.append(block)
            }
        }

        return blocks.joined(separator: "\n")
    }

    private mutating func parseCodeBlock() -> String? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard let fence = codeFenceInfo(from: trimmed) else {
            return nil
        }

        index += 1
        var content: [String] = []

        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            if current.hasPrefix(String(repeating: fence.marker, count: fence.length)) {
                index += 1
                break
            }

            content.append(lines[index])
            index += 1
        }

        let languageAttribute = fence.language.isEmpty ? "" : " class=\"language-\(InlineRenderer.escapeAttribute(fence.language))\""
        let escapedBody = InlineRenderer.escape(content.joined(separator: "\n"))
        return "<pre><code\(languageAttribute)>\(escapedBody)</code></pre>"
    }

    private mutating func parseHeading() -> String? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        let level = hashes.count

        guard (1...6).contains(level), trimmed.dropFirst(level).first == " " else {
            return nil
        }

        index += 1
        let content = trimmed.dropFirst(level + 1)
        return "<h\(level)>\(InlineRenderer.render(String(content)))</h\(level)>"
    }

    private mutating func parseHorizontalRule() -> String? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, Set(compact).count == 1, ["-", "*", "_"].contains(String(compact.first!)) else {
            return nil
        }

        index += 1
        return "<hr>"
    }

    private mutating func parseTable() -> String? {
        guard index + 1 < lines.count else {
            return nil
        }

        let headerLine = lines[index]
        let separatorLine = lines[index + 1]
        let headerCells = splitTableRow(headerLine)
        let separatorCells = splitTableRow(separatorLine)

        guard !headerCells.isEmpty,
              headerCells.count == separatorCells.count,
              separatorCells.allSatisfy({ isTableSeparator($0) }) else {
            return nil
        }

        index += 2
        var bodyRows: [[String]] = []

        while index < lines.count {
            let cells = splitTableRow(lines[index])
            if cells.count == headerCells.count {
                bodyRows.append(cells)
                index += 1
            } else {
                break
            }
        }

        let headerHTML = headerCells
            .map { "<th>\(InlineRenderer.render($0))</th>" }
            .joined()
        let bodyHTML = bodyRows.map { row in
            let cells = row.map { "<td>\(InlineRenderer.render($0))</td>" }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()

        return """
        <table>
          <thead><tr>\(headerHTML)</tr></thead>
          <tbody>\(bodyHTML)</tbody>
        </table>
        """
    }

    private mutating func parseCalloutOrQuote() -> String? {
        guard lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") else {
            return nil
        }

        var quoteLines: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                var line = trimmed.dropFirst()
                if line.first == " " {
                    line = line.dropFirst()
                }
                quoteLines.append(String(line))
                index += 1
            } else if trimmed.isEmpty {
                quoteLines.append("")
                index += 1
            } else {
                break
            }
        }

        if let first = quoteLines.first,
           let callout = parseCalloutHeader(first) {
            var nested = MarkdownParser(markdown: quoteLines.dropFirst().joined(separator: "\n"))
            let innerHTML = nested.renderDocument()
            let title = InlineRenderer.render(callout.title)
            return """
            <div class="callout callout-\(InlineRenderer.escapeAttribute(callout.kind))">
              <div class="callout-title">\(title)</div>
              <div class="callout-body">\(innerHTML)</div>
            </div>
            """
        }

        var nested = MarkdownParser(markdown: quoteLines.joined(separator: "\n"))
        return "<blockquote>\(nested.renderDocument())</blockquote>"
    }

    private mutating func parseUnorderedList() -> String? {
        guard unorderedListItemText(from: lines[index]) != nil else {
            return nil
        }

        var items: [String] = []
        while index < lines.count, let item = unorderedListItemText(from: lines[index]) {
            items.append(parseListItem(startingWith: item))
        }

        let html = items.map { "<li>\($0)</li>" }.joined()
        return "<ul>\(html)</ul>"
    }

    private mutating func parseOrderedList() -> String? {
        guard orderedListItemText(from: lines[index]) != nil else {
            return nil
        }

        var items: [String] = []
        while index < lines.count, let item = orderedListItemText(from: lines[index]) {
            items.append(parseListItem(startingWith: item))
        }

        let html = items.map { "<li>\($0)</li>" }.joined()
        return "<ol>\(html)</ol>"
    }

    private mutating func parseParagraph() -> String? {
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            if isBlank(line) || startsNewBlock(line, at: index) {
                break
            }

            paragraphLines.append(line)
            index += 1
        }

        guard !paragraphLines.isEmpty else {
            return nil
        }

        var output = ""
        for (lineIndex, line) in paragraphLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if lineIndex > 0 {
                output += "<br>"
            }
            output += InlineRenderer.render(trimmed)
        }

        return "<p>\(output)</p>"
    }

    private mutating func parseListItem(startingWith firstLineText: String) -> String {
        index += 1
        var parts = [firstLineText]

        while index < lines.count {
            let line = lines[index]
            if isBlank(line) {
                index += 1
                break
            }

            if startsNewBlock(line, at: index) || unorderedListItemText(from: line) != nil || orderedListItemText(from: line) != nil {
                break
            }

            if line.hasPrefix("  ") || line.hasPrefix("\t") {
                parts.append(line.trimmingCharacters(in: .whitespaces))
                index += 1
            } else {
                break
            }
        }

        return InlineRenderer.render(parts.joined(separator: " "))
    }

    private func startsNewBlock(_ line: String, at position: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") { return true }
        if unorderedListItemText(from: line) != nil { return true }
        if orderedListItemText(from: line) != nil { return true }
        if codeFenceInfo(from: trimmed) != nil { return true }
        if headingStart(from: trimmed) != nil { return true }
        if horizontalRule(from: trimmed) { return true }
        if tableStart(at: position) { return true }
        return false
    }

    private func headingStart(from trimmed: String) -> Int? {
        let hashes = trimmed.prefix { $0 == "#" }
        let count = hashes.count
        guard (1...6).contains(count), trimmed.dropFirst(count).first == " " else {
            return nil
        }
        return count
    }

    private func horizontalRule(from trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && Set(compact).count == 1 && compact.first.map { ["-", "*", "_"].contains(String($0)) } == true
    }

    private func tableStart(at position: Int) -> Bool {
        guard position + 1 < lines.count else {
            return false
        }

        let headerCells = splitTableRow(lines[position])
        let separatorCells = splitTableRow(lines[position + 1])
        return !headerCells.isEmpty && headerCells.count == separatorCells.count && separatorCells.allSatisfy(isTableSeparator)
    }

    private func unorderedListItemText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, ["-", "*", "+"].contains(first), trimmed.dropFirst().first == " " else {
            return nil
        }

        return String(trimmed.dropFirst(2))
    }

    private func orderedListItemText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var digits = ""

        for character in trimmed {
            if character.isNumber {
                digits.append(character)
            } else {
                break
            }
        }

        guard !digits.isEmpty else {
            return nil
        }

        let remainder = trimmed.dropFirst(digits.count)
        guard remainder.first == ".", remainder.dropFirst().first == " " else {
            return nil
        }

        return String(remainder.dropFirst(2))
    }

    private func splitTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return []
        }

        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return stripped
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isTableSeparator(_ cell: String) -> Bool {
        let compact = cell.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else {
            return false
        }

        let trimmed = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
        return trimmed.isEmpty && compact.contains("-")
    }

    private func parseCalloutHeader(_ line: String) -> (kind: String, title: String)? {
        guard line.hasPrefix("[!") else {
            return nil
        }

        guard let closingBracket = line.firstIndex(of: "]") else {
            return nil
        }

        let kind = String(line[line.index(line.startIndex, offsetBy: 2)..<closingBracket]).lowercased()
        let remainder = line[line.index(after: closingBracket)...].trimmingCharacters(in: .whitespaces)
        let title = remainder.isEmpty ? kind.capitalized : remainder
        return (kind, title)
    }

    private func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func codeFenceInfo(from trimmed: String) -> (marker: Character, length: Int, language: String)? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else {
            return nil
        }

        let prefix = trimmed.prefix { $0 == marker }
        guard prefix.count >= 3 else {
            return nil
        }

        let language = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return (marker, prefix.count, language)
    }
}

private enum InlineRenderer {
    static func render(_ text: String) -> String {
        var working = text
        var placeholders: [String: String] = [:]
        var placeholderIndex = 0

        func stash(_ html: String) -> String {
            let token = "\u{E000}\(placeholderIndex)\u{E001}"
            placeholderIndex += 1
            placeholders[token] = html
            return token
        }

        working = replace(pattern: #"(`+)(.+?)\1"#, in: working, options: [.dotMatchesLineSeparators]) { groups in
            stash("<code>\(escape(groups[1]))</code>")
        }

        working = escape(working)

        working = replace(pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]+)")?\)"#, in: working) { groups in
            let alt = groups[0]
            let source = groups[1]
            let title = groups.count > 2 ? " title=\"\(escapeAttribute(groups[2]))\"" : ""
            return stash("<img src=\"\(escapeAttribute(source))\" alt=\"\(escapeAttribute(alt))\"\(title)>")
        }

        working = replace(pattern: #"\[([^\]]+)\]\(([^)\s]+)(?:\s+"([^"]+)")?\)"#, in: working) { groups in
            let label = groups[0]
            let href = groups[1]
            let title = groups.count > 2 ? " title=\"\(escapeAttribute(groups[2]))\"" : ""
            return "<a href=\"\(escapeAttribute(href))\"\(title)>\(label)</a>"
        }

        working = replace(pattern: #"\[\[([^\]|#]+)(?:#([^\]|]+))?(?:\|([^\]]+))?\]\]"#, in: working) { groups in
            let target = groups[0]
            let heading = groups.count > 1 ? groups[1] : ""
            let label = groups.count > 2 ? groups[2] : target
            let fragment = heading.isEmpty ? "" : "#\(escapeAttribute(slugify(heading)))"
            let href = "\(escapeAttribute(target)).md\(fragment)"
            return "<a href=\"\(href)\">\(label)</a>"
        }

        working = replace(pattern: #"==(.+?)=="#, in: working) { groups in
            "<mark>\(groups[0])</mark>"
        }

        working = replace(pattern: #"~~(.+?)~~"#, in: working) { groups in
            "<del>\(groups[0])</del>"
        }

        working = replace(pattern: #"\*\*(.+?)\*\*"#, in: working) { groups in
            "<strong>\(groups[0])</strong>"
        }

        working = replace(pattern: #"__(.+?)__"#, in: working) { groups in
            "<strong>\(groups[0])</strong>"
        }

        working = replace(pattern: #"(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)"#, in: working) { groups in
            "<em>\(groups[0])</em>"
        }

        working = replace(pattern: #"(?<!_)_(?!\s)(.+?)(?<!\s)_(?!_)"#, in: working) { groups in
            "<em>\(groups[0])</em>"
        }

        working = replace(pattern: #"(?<!["'=])(https?://[^\s<]+)"#, in: working) { groups in
            let href = groups[0]
            return "<a href=\"\(escapeAttribute(href))\">\(href)</a>"
        }

        for (token, html) in placeholders {
            working = working.replacingOccurrences(of: token, with: html)
        }

        return working
    }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ string: String) -> String {
        escape(string).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func replace(
        pattern: String,
        in string: String,
        options: NSRegularExpression.Options = [],
        using transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return string
        }

        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else {
            return string
        }

        var result = string
        for match in matches.reversed() {
            let groups = (1..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                guard range.location != NSNotFound else {
                    return ""
                }
                return nsString.substring(with: range)
            }

            let replacement = transform(groups)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }

        return result
    }

    private static func slugify(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        return string
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}
