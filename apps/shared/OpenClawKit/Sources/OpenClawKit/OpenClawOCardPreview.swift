import Foundation

/// Fork: sample day-thread cards for simulator screenshots (`--openclaw-ocard-fixture` on iOS,
/// `--openclaw-watch-ocard-fixture` on watchOS). Synthetic content only.
public enum OpenClawOCardPreview {
    public struct Entry: Sendable {
        public var role: String
        public var text: String
    }

    /// Sample "Pracuje teraz" card (two agents working).
    public static func workNowCard(now: Date = Date()) -> OpenClawOCard? {
        let ts = now.timeIntervalSince1970
        return OpenClawWorkItem.watchCard(
            for: [
                OpenClawWorkItem(
                    agent: "kodowanie",
                    name: "Układ PDF karty pracy (X21)",
                    status: "pracuje",
                    since: ts - 12 * 60,
                    url: "https://example.invalid/chat/kodowanie/~key/dashboard/preview-x21"),
                OpenClawWorkItem(
                    agent: "lpng-dane",
                    name: "Plan kursu na listopad (X22)",
                    status: "pracuje",
                    since: ts - 3 * 60,
                    url: "https://example.invalid/chat/lpng-dane/~key/dashboard/preview-x22"),
            ],
            now: now)
    }

    public static func entries(now: Date = Date()) -> [Entry] {
        let ts = now.timeIntervalSince1970
        let cards: [OpenClawOCard] = [
            OpenClawOCard(
                kind: .question,
                group: "X21",
                title: "Układ PDF karty pracy (X21)",
                agent: "kodowanie",
                question: "Który układ PDF wdrożyć dla karty pracy z obrazkami?",
                options: ["Wariant A — 2 kolumny", "Wariant B — 1 kolumna, większe obrazki", "Pokaż oba jeszcze raz"],
                pullRequests: ["https://github.com/example/lp-ng/pull/2201"],
                threadKey: "agent:kodowanie:dashboard:preview-x21",
                timestamp: ts - 120),
            OpenClawOCard(
                kind: .pr,
                group: "X19",
                title: "Filtr po grupie na liście uczniów (X19)",
                agent: "lpng-koder",
                summary: "Dodany filtr po grupie i sortowanie po dacie ostatniej lekcji. "
                    + "Build zielony, trzy zrzuty w PR.",
                pullRequests: ["https://github.com/example/lp-ng/pull/2198"],
                threadKey: "agent:lpng-koder:dashboard:preview-x19",
                timestamp: ts - 400),
            OpenClawOCard(
                kind: .error,
                group: "X17",
                title: "Rotacja kopii zapasowych",
                agent: "infra",
                summary: "Przerwane: za mało miejsca na dysku kopii. Nic nie zostało usunięte.",
                threadKey: "agent:infra:dashboard:preview-x17",
                timestamp: ts - 1100),
            OpenClawOCard(
                kind: .done,
                group: "X16",
                title: "Przypomnienie w kalendarzu",
                agent: "asystent",
                summary: "Dodane wydarzenie „Zebranie” na jutro o 18:00 z powiadomieniem.",
                threadKey: "agent:asystent:dashboard:preview-x16",
                timestamp: ts - 700),
            OpenClawOCard(
                kind: .start,
                group: "X22",
                title: "Zlecone: plan kursu na listopad",
                agent: "lpng-dane",
                threadKey: "agent:lpng-dane:dashboard:preview-x22",
                timestamp: ts - 1500),
        ]
        var entries = [
            Entry(role: "user", text: "Co dziś na mnie czeka?"),
            Entry(
                role: "assistant",
                text: "Masz jedną decyzję, jeden gotowy PR i jeden błąd do ponowienia. Szczegóły w kartach poniżej."),
        ]
        // Oldest first, so the question and the PR sit next to the composer.
        for card in cards.sorted(by: { ($0.ts ?? 0) < ($1.ts ?? 0) }) {
            guard let marker = OpenClawOCardMarker.encode(card) else { continue }
            entries.append(Entry(role: "assistant", text: "\(card.title)\n\n\(marker)"))
        }
        return entries
    }
}
