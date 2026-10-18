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
        /// Synthetic "Pracuje teraz" card built by the app (never posted by the host).
        case work
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
            case .work: "⏳"
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

    /// Smaller copy for the Watch: WatchConnectivity payloads stay small and images are dropped.
    public var watchCompact: OpenClawOCard {
        OpenClawOCard(
            kind: self.kind,
            title: String(self.title.prefix(80)),
            agent: self.agent,
            summary: self.summary.map { String($0.prefix(160)) },
            question: self.question.map { String($0.prefix(200)) },
            options: self.options.prefix(4).map { String($0.prefix(60)) },
            pullRequests: Array(self.pullRequests.prefix(2)),
            threadKey: self.threadKey,
            timestamp: self.ts)
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
        case .work: "⏳ pracuje"
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
        case .work: "⏳"
        }
    }

    /// Low-priority kinds render as a single compact row, like the web cards.
    public var isCompact: Bool {
        self == .info || self == .start
    }
}

/// Fork: the owner's day thread is the `asystent` agent's dashboard session for today.
public enum OpenClawDayThread {
    public static let agentID = "asystent"

    public static func agentID(of sessionKey: String?) -> String? {
        let parts = (sessionKey ?? "").split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0].lowercased() == "agent" else { return nil }
        let agent = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return agent.isEmpty ? nil : agent
    }

    /// Agent threads opened from cards are any other agent's sessions.
    public static func isAgentThread(_ sessionKey: String?) -> Bool {
        guard let agent = self.agentID(of: sessionKey) else { return false }
        return agent.lowercased() != self.agentID
    }

    /// Control UI link `…/chat/<agent>/~key/<rest>` → session key `agent:<agent>:<rest>`.
    public static func threadKey(fromControlUIURL url: String?) -> String? {
        guard let url, let range = url.range(of: "/chat/") else { return nil }
        let parts = url[range.upperBound...].split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[1] == "~key", !parts[0].isEmpty else { return nil }
        let rest = parts[2...].map { $0.removingPercentEncoding ?? $0 }
        return (["agent", parts[0]] + rest).joined(separator: ":")
    }
}

/// Fork: thread lookup for cards without their own thread key, like the web cards: a group's
/// thread comes from any card of that group that has one; PR-tracking cards (group = PR URL)
/// join the task whose card listed that PR, or the task named "(X18)" in their title.
public struct OpenClawOCardThreadIndex: Sendable, Equatable {
    private var keysByGroup: [String: String] = [:]
    private var groupsByPullRequest: [String: String] = [:]

    public init() {}

    public init(cards: [OpenClawOCard]) {
        for card in cards {
            guard let group = card.g, !Self.isURLGroup(group) else { continue }
            if let key = card.threadKey, self.keysByGroup[group] == nil {
                self.keysByGroup[group] = key
            }
            for url in card.pullRequests where self.groupsByPullRequest[Self.normalized(url)] == nil {
                self.groupsByPullRequest[Self.normalized(url)] = group
            }
        }
    }

    public var isEmpty: Bool {
        self.keysByGroup.isEmpty
    }

    public func threadKey(for card: OpenClawOCard) -> String? {
        if let key = card.threadKey { return key }
        guard let group = self.taskGroup(for: card) else { return nil }
        return self.keysByGroup[group]
    }

    private func taskGroup(for card: OpenClawOCard) -> String? {
        guard let group = card.g else { return nil }
        guard Self.isURLGroup(group) else { return group }
        if let task = self.groupsByPullRequest[Self.normalized(group)] { return task }
        return Self.taskTag(in: card.title)
    }

    /// "(X18)" in a title.
    static func taskTag(in title: String) -> String? {
        guard let open = title.range(of: "(X") else { return nil }
        let digits = title[open.upperBound...].prefix { $0.isNumber }
        guard !digits.isEmpty,
              title[open.upperBound...].dropFirst(digits.count).first == ")"
        else { return nil }
        return "X\(digits)"
    }

    private static func isURLGroup(_ group: String) -> Bool {
        group.lowercased().hasPrefix("http")
    }

    private static func normalized(_ url: String) -> String {
        url.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
    }
}

/// Fork: "Pracuje teraz" — live work from the Gateway host (`/agent-panel-live/agent-claude-data.json`,
/// field `dzien.items`), the same source as the web bar.
public struct OpenClawWorkItem: Decodable, Sendable, Equatable, Identifiable {
    public var agent: String?
    public var name: String?
    public var status: String?
    public var since: Double?
    public var step: String?
    public var url: String?
    public var pr: String?

    public init(agent: String?, name: String?, status: String?, since: Double?, step: String? = nil, url: String?) {
        self.agent = agent
        self.name = name
        self.status = status
        self.since = since
        self.step = step
        self.url = url
        self.pr = nil
    }

    public var id: String {
        [self.agent, self.name, self.url, self.since.map { String($0) }].compactMap(\.self).joined(separator: "|")
    }

    public var isWorking: Bool {
        self.status == "pracuje"
    }

    public var threadKey: String? {
        OpenClawDayThread.threadKey(fromControlUIURL: self.url)
    }

    /// "12 min", "2 h 5 min".
    public func elapsedText(now: Date = Date()) -> String? {
        guard let since, since > 0 else { return nil }
        let minutes = max(0, Int(now.timeIntervalSince1970 - since) / 60)
        if minutes < 1 { return "teraz" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    public static func decodeWorking(from data: Data) -> [OpenClawWorkItem]? {
        struct Payload: Decodable {
            struct Day: Decodable {
                var items: [OpenClawWorkItem]?
            }

            var dzien: Day?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return (payload.dzien?.items ?? []).filter(\.isWorking)
    }

    /// Watch card summarizing the work in progress (one line per item).
    public static func watchCard(for items: [OpenClawWorkItem], now: Date = Date()) -> OpenClawOCard? {
        guard !items.isEmpty else { return nil }
        let lines = items.prefix(4).map { item in
            [item.agent, item.name.map { String($0.prefix(40)) }, item.elapsedText(now: now)]
                .compactMap(\.self)
                .joined(separator: " · ")
        }
        return OpenClawOCard(
            kind: .work,
            title: "Pracuje teraz · \(items.count)",
            summary: lines.joined(separator: "\n"),
            threadKey: items.count == 1 ? items[0].threadKey : nil,
            timestamp: now.timeIntervalSince1970)
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

    /// Marker-only text carrying a compact card, for Watch chat items.
    public static func watchText(for card: OpenClawOCard) -> String {
        self.encode(card.watchCompact) ?? card.plainText
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
