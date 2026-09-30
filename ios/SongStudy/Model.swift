import Foundation

let defaultLadder = [
    "just listen — no notes",
    "form — where are the sections",
    "drums only",
    "bass only",
    "lyrics",
    "lead vocal + harmony production",
    "arrangement — what enters, what leaves",
    "the mix — where is everything",
    "the moment you keep returning to",
    "free — write the thesis",
]

struct Note: Identifiable, Equatable {
    var id = UUID()
    var t: Double
    var text: String
    var pass: Int
    var star = false

    /// A note starting with "=" names a section: "=chorus".
    var isSection: Bool { text.range(of: #"^=\s*\S"#, options: .regularExpression) != nil }
    var sectionName: String {
        let s = text.replacingOccurrences(of: #"^=\s*"#, with: "", options: .regularExpression)
        return (s.components(separatedBy: "\n").first ?? s).trimmingCharacters(in: .whitespaces)
    }
    var key: String { "\(pass)|\(Int((t * 10).rounded()))|\(text)" }
}

struct Study {
    var title: String
    var fileName: String
    var duration: Double = 0
    var pass = 1
    var targetPasses = 10
    var lag = 1.5
    var ladder = defaultLadder
    var filters: [Int: String] = [:]      // kept for the web app; not applied on the phone yet
    var notes: [Note] = []

    var done: Bool { pass > targetPasses }
    var sections: [Note] { notes.filter(\.isSection).sorted { $0.t < $1.t } }

    func prompt(for p: Int) -> String { p >= 1 && p <= ladder.count ? ladder[p - 1] : "" }
    mutating func setPrompt(_ s: String, for p: Int) {
        guard p >= 1 else { return }
        while ladder.count < p { ladder.append("") }
        ladder[p - 1] = s
    }
}

// MARK: - formatting shared with the web app

/// 0:59.96 renders as 1:00.0, never 0:60.0 — round to tenths before splitting.
func fmt(_ s0: Double, _ dec: Bool = false) -> String {
    let s = (s0.isFinite && s0 >= 0) ? s0 : 0
    if dec {
        let tenths = Int((s * 10).rounded())
        let m = tenths / 600
        return "\(m):" + String(format: "%04.1f", Double(tenths - m * 600) / 10)
    }
    let whole = Int(s.rounded(.down))
    return "\(whole / 60):" + String(format: "%02d", whole % 60)
}

/// Numbers the way JavaScript prints them: 2 not 2.0, 1.75 not 1.7500.
func jsNum(_ d: Double) -> String {
    if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
    return "\(d)"
}

private let tagRx = try! NSRegularExpression(pattern: #"#([\p{L}\p{N}_-]+)"#)
func parseTags(_ text: String) -> [String] {
    let ns = text as NSString
    return tagRx.matches(in: text, range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range(at: 1)).lowercased() }
}
