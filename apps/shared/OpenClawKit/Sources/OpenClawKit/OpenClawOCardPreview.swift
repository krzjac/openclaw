import Foundation

/// Fork: sample day-thread cards for simulator screenshots (`--openclaw-ocard-fixture` on iOS,
/// `--openclaw-watch-ocard-fixture` on watchOS). Synthetic content only.
public enum OpenClawOCardPreview {
    public struct Entry: Sendable {
        public var role: String
        public var text: String
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
                timestamp: ts - 1500),
            OpenClawOCard(
                kind: .pr,
                group: "X19",
                title: "Filtr po grupie na liście uczniów (X19)",
                agent: "lpng-koder",
                summary: "Dodany filtr po grupie i sortowanie po dacie ostatniej lekcji. "
                    + "Build zielony, trzy zrzuty w PR.",
                pullRequests: ["https://github.com/example/lp-ng/pull/2198"],
                threadKey: "agent:lpng-koder:dashboard:preview-x19",
                timestamp: ts - 1100),
            OpenClawOCard(
                kind: .error,
                group: "X17",
                title: "Rotacja kopii zapasowych",
                agent: "infra",
                summary: "Przerwane: za mało miejsca na dysku kopii. Nic nie zostało usunięte.",
                threadKey: "agent:infra:dashboard:preview-x17",
                timestamp: ts - 700),
            OpenClawOCard(
                kind: .done,
                group: "X16",
                title: "Przypomnienie w kalendarzu",
                agent: "asystent",
                summary: "Dodane wydarzenie „Zebranie” na jutro o 18:00 z powiadomieniem.",
                threadKey: "agent:asystent:dashboard:preview-x16",
                timestamp: ts - 400),
            OpenClawOCard(
                kind: .start,
                group: "X22",
                title: "Zlecone: plan kursu na listopad",
                agent: "lpng-dane",
                threadKey: "agent:lpng-dane:dashboard:preview-x22",
                timestamp: ts - 120),
        ]
        var entries = [
            Entry(role: "user", text: "Co dziś na mnie czeka?"),
            Entry(
                role: "assistant",
                text: "Masz jedną decyzję, jeden gotowy PR i jeden błąd do ponowienia. Szczegóły w kartach poniżej."),
        ]
        for card in cards {
            guard let marker = OpenClawOCardMarker.encode(card) else { continue }
            entries.append(Entry(role: "assistant", text: "\(card.title)\n\n\(marker)"))
        }
        return entries
    }
}
