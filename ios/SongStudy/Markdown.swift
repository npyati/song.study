import Foundation

/// The .notes.md format, shared byte-for-byte with the web app.
/// YAML frontmatter, then "## Pass N — prompt" sections, one note per list item.
enum MD {
    // JSON strings are valid YAML double-quoted scalars.
    static func yq(_ s: String) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
           let out = String(data: d, encoding: .utf8) { return out }
        return "\"\(s)\""
    }

    static func unq(_ v: String?) -> String? {
        guard let raw = v?.trimmingCharacters(in: .whitespaces) else { return nil }
        if raw.hasPrefix("\"") {
            if let d = raw.data(using: .utf8),
               let s = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) as? String { return s }
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func write(_ st: Study, now: Date = Date()) -> String {
        var head = [
            "---",
            "title: \(yq(st.title))",
            "file: \(yq(st.fileName))",
            "duration: " + String(format: "%.2f", st.duration),
            "pass: \(st.pass)",
            "targetPasses: \(st.targetPasses)",
            "lag: \(jsNum(st.lag))",
            "updated: \(iso.string(from: now))",
            "prompts:",
        ]
        for (i, p) in st.ladder.enumerated() { head.append("  \(i + 1): \(yq(p))") }
        let fk = st.filters.keys.filter { $0 > 0 }.sorted()
        if !fk.isEmpty {
            head.append("filters:")
            for k in fk { head.append("  \(k): \(st.filters[k]!)") }
        }
        head.append("---")
        head.append("")

        var body = ["# \(st.title)", ""]
        for p in Set(st.notes.map(\.pass)).sorted() {
            let prompt = st.prompt(for: p)
            body.append("## Pass \(p)" + (prompt.isEmpty ? "" : " — " + prompt))
            body.append("")
            for n in st.notes.filter({ $0.pass == p }).sorted(by: { $0.t < $1.t }) {
                // continuation lines are indented two spaces; blank lines inside a note stay blank
                let lines = n.text.components(separatedBy: "\n").enumerated().map { i, l in
                    i == 0 ? l : (l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "  " + l)
                }
                body.append("- " + (n.star ? "\u{2605} " : "") + "**[\(fmt(n.t, true))]** " + lines.joined(separator: "\n"))
            }
            body.append("")
        }
        return head.joined(separator: "\n") + body.joined(separator: "\n")
    }

    private static let passRx = try! NSRegularExpression(pattern: #"^##\s+Pass\s+(\d+)"#, options: .caseInsensitive)
    private static let noteRx = try! NSRegularExpression(pattern: #"^-\s+(\x{2605}\s+)?\*\*\[(\d+):(\d+(?:\.\d+)?)\]\*\*\s?([\s\S]*)$"#)
    private static let promptRx = try! NSRegularExpression(pattern: #"^[ ]{2}(\d+):[ ]?(.*)$"#)
    private static let filterRx = try! NSRegularExpression(pattern: #"^[ ]{2}(\d+):[ ]*(\S.*)$"#)

    private static func groups(_ rx: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /// parseFloat semantics: the longest numeric prefix.
    private static func leadingDouble(_ s: String?) -> Double? {
        guard let s else { return nil }
        let sc = Scanner(string: s)
        return sc.scanDouble()
    }

    static func parse(_ raw: String, fileName: String) -> Study {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var title = fileName.replacingOccurrences(of: #"\.notes\.md$"#, with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"\.md$"#, with: "", options: [.regularExpression, .caseInsensitive])
        var st = Study(title: title, fileName: fileName)

        var body = text
        if text.hasPrefix("---\n"), text.count >= 4 {
            let from = text.index(text.startIndex, offsetBy: 4)
            if let close = text.range(of: "\n---", range: from..<text.endIndex) {
                let block = String(text[from..<close.lowerBound])
                var rest = text[close.upperBound...]
                if rest.hasPrefix("\n") { rest = rest.dropFirst() }
                body = String(rest)

                let lines = block.components(separatedBy: "\n")
                func get(_ k: String) -> String? {
                    for l in lines where l.hasPrefix(k + ":") {
                        return String(l.dropFirst(k.count + 1)).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                    }
                    return nil
                }
                if let t = unq(get("title")), !t.isEmpty { st.title = t }
                if let f = unq(get("file")), !f.isEmpty { st.fileName = f }
                st.duration = leadingDouble(get("duration")) ?? 0
                st.pass = max(1, Int((leadingDouble(get("pass")) ?? 1).rounded()))
                st.targetPasses = max(1, Int((leadingDouble(get("targetPasses")) ?? 10).rounded()))
                st.lag = leadingDouble(get("lag")) ?? 1.5

                func indentedBlock(after header: String) -> [String] {
                    guard let i = lines.firstIndex(of: header) else { return [] }
                    var out: [String] = []
                    for l in lines[(i + 1)...] {
                        guard l.range(of: #"^[ ]{2}\d+:"#, options: .regularExpression) != nil else { break }
                        out.append(l)
                    }
                    return out
                }
                var ladder: [Int: String] = [:]
                for l in indentedBlock(after: "prompts:") {
                    if let g = groups(promptRx, l), let n = Int(g[1] ?? "") { ladder[n - 1] = unq(g[2] ?? "") ?? "" }
                }
                if let top = ladder.keys.max(), top >= 0 {
                    st.ladder = (0...top).map { ladder[$0] ?? "" }
                }
                for l in indentedBlock(after: "filters:") {
                    if let g = groups(filterRx, l), let n = Int(g[1] ?? ""), let v = g[2] {
                        st.filters[n] = v.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        var pass = 1
        let lines = body.components(separatedBy: "\n")
        func cont(_ j: Int) -> Bool {
            j < lines.count && lines[j].hasPrefix("  ") && !lines[j].trimmingCharacters(in: .whitespaces).isEmpty
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let g = groups(passRx, line), let n = Int(g[1] ?? "") { pass = n; i += 1; continue }
            guard let g = groups(noteRx, line) else { i += 1; continue }
            var txt = g[4] ?? ""
            while true {
                // blank lines belong to the note only if an indented continuation follows
                var j = i + 1
                while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                if !cont(j) { break }
                for _ in (i + 1)..<j { txt += "\n" }
                txt += "\n" + String(lines[j].dropFirst(2))
                i = j
            }
            txt = txt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !txt.isEmpty {
                let t = Double(Int(g[2] ?? "0") ?? 0) * 60 + (Double(g[3] ?? "0") ?? 0)
                st.notes.append(Note(t: t, text: txt, pass: pass, star: g[1] != nil))
            }
            i += 1
        }
        st.notes.sort { $0.t < $1.t }
        return st
    }
}
