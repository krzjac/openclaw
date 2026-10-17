import Foundation

/// Fork: rich cards posted by the owner's Gateway host scripts (day thread, task dispatcher).
/// A card message is readable fallback text plus an `ocard:<base64url JSON>` marker, usually
/// wrapped in backticks. The web Control UI draws a card from the marker; native clients do the
/// same and never show the raw marker.
public struct OpenClawOCard: Codable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case question
        case pr
        case done
        case error
        case info
        case start
        case night
        case cal
    }

    public var v: Int?
    public var k: String?
    public var g: String?
    public var t: String?
    public var a: String?
    public var s: String?
    public var q: String?
    public var o: [String]?
    public var p: [String]?
    public var key: String?
    public var m: [String]?
    public var ts: Double?

    public init(
        kind: Kind,
        group: String? = nil,
        title: String,
        agent: String? = nil,
        summary: String? = nil,
        question: String? = nil,
        options: [String]? = nil,
        pullRequests: [String]? = nil,
        threadKey: String? = nil,
        images: [String]? = nil,
        timestamp: Double? = nil)
    {
        self.v = 1
        self.k = kind.rawValue
        self.g = group
        self.t = title
        self.a = agent
        self.s = summary
        self.q = question
        self.o = options
        self.p = pullRequests
        self.key = threadKey
        self.m = images
        self.ts = timestamp
    }

    public var kind: Kind {
        self.k.flatMap(Kind.init(rawValue:)) ?? .info
    }

    public var title: String {
        Self.trimmed(self.t) ?? self.kind.statusLabel
    }

    public var agent: String? {
        Self.trimmed(self.a)
    }

    public var summary: String? {
        Self.trimmed(self.s)
    }

    public var question: String? {
        Self.trimmed(self.q)
    }

    /// Question text for question cards, otherwise the summary.
    public var bodyText: String? {
        self.kind == .question ? (self.question ?? self.summary) : self.summary
    }

    public var options: [String] {
        (self.o ?? []).compactMap { Self.trimmed($0) }
    }

    public var pullRequests: [String] {
        (self.p ?? []).compactMap { Self.trimmed($0) }
    }

    public var threadKey: String? {
        Self.trimmed(self.key)
    }

    public var images: [URL] {
        (self.m ?? []).compactMap { raw in
            guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
            return url
        }
    }

    public var date: Date? {
        guard let ts, ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    /// Agent badge, matching the web card icons.
    public var agentGlyph: String {
        switch self.agent {
        case "kodowanie", "lpng-koder": "🛠️"
        case "lpng-dane", "lpng": "🧩"
        case "asystent": "🗓️"
        case "test": "🧪"
        case "marketing": "📣"
        case "infra": "🧰"
        default:
            switch self.kind {
            case .info: "🟣"
            case .night: "🌙"
            case .pr: "🔀"
            case .cal: "📅"
            default: "🤖"
            }
        }
    }

    /// Marker-free text for previews, search, copy, speech, notifications, and the Watch.
    public var plainText: String {
        var lines = ["\(self.kind.glyph) \(self.title)"]
        if let body = self.bodyText {
            lines.append(body)
        }
        if self.kind == .question, !self.options.isEmpty {
            lines.append(self.options.map { "• \($0)" }.joined(separator: "\n"))
        }
        lines.append(contentsOf: self.pullRequests.map(Self.pullRequestLabel))
        return lines.joined(separator: "\n")
    }

    /// `owner/repo/pull/12` → `repo #12`; other links stay as they are.
    public static func pullRequestLabel(_ url: String) -> String {
        guard let parsed = URL(string: url), parsed.host?.lowercased() == "github.com" else { return url }
        let parts = parsed.path.split(separator: "/")
        guard parts.count >= 4, parts[2] == "pull" else { return url }
        return "\(parts[1]) #\(parts[3])"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension OpenClawOCard.Kind {
    /// Status chip text, matching the web cards.
    public var statusLabel: String {
        switch self {
        case .question: "❓ czeka na Ciebie"
        case .pr: "PR gotowy"
        case .done: "✓ zrobione"
        case .error: "⚠ błąd"
        case .info: "✓"
        case .start: "▶ zlecone"
        case .night: "🌙 w nocy"
        case .cal: "📅 zmiana"
        }
    }

    public var glyph: String {
        switch self {
        case .question: "❓"
        case .pr: "🔀"
        case .done: "✅"
        case .error: "⚠️"
        case .info: "ℹ️"
        case .start: "▶️"
        case .night: "🌙"
        case .cal: "📅"
        }
    }

    /// Low-priority kinds render as a single compact row, like the web cards.
    public var isCompact: Bool {
        self == .info || self == .start
    }
}

public enum OpenClawOCardMarker {
    public struct Match: Sendable, Equatable {
        public var card: OpenClawOCard
        /// Message text without the marker (the readable fallback the host script wrote).
        public var fallbackText: String
    }

    private static let prefix = "ocard:"

    public static func containsMarker(_ text: String) -> Bool {
        text.contains(self.prefix)
    }

    public static func extract(from text: String) -> Match? {
        guard let range = text.range(of: self.prefix) else { return nil }
        var end = range.upperBound
        while end < text.endIndex, self.isBase64URL(text[end]) {
            end = text.index(after: end)
        }
        let payload = String(text[range.upperBound..<end])
        guard !payload.isEmpty, let card = self.decode(payload) else { return nil }
        var lower = range.lowerBound
        if lower > text.startIndex, text[text.index(before: lower)] == "`" {
            lower = text.index(before: lower)
        }
        var upper = end
        if upper < text.endIndex, text[upper] == "`" {
            upper = text.index(after: upper)
        }
        var fallback = text
        fallback.removeSubrange(lower..<upper)
        return Match(card: card, fallbackText: fallback.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Replaces a card message with its marker-free plain text; other text is returned unchanged.
    public static func plainText(from text: String) -> String {
        guard self.containsMarker(text), let match = self.extract(from: text) else { return text }
        return match.card.plainText
    }

    public static func encode(_ card: OpenClawOCard) -> String? {
        guard let data = try? JSONEncoder().encode(card) else { return nil }
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "`\(self.prefix)\(base64)`"
    }

    static func decode(_ payload: String) -> OpenClawOCard? {
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(OpenClawOCard.self, from: data)
    }

    private static func isBase64URL(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}
