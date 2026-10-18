import OpenClawKit
import SwiftUI

/// Fork: Watch actions for day-thread cards. The App sends them to the iPhone, which calls the
/// owner's Gateway host API and switches the Watch between the day thread and agent threads.
struct ForkWatchActions {
    /// nil returns to the day thread.
    var openThread: @MainActor (_ threadKey: String?) -> Void = { _ in }
    var answer: @MainActor (_ threadKey: String, _ text: String) -> Void = { _, _ in }
}

extension EnvironmentValues {
    @Entry var forkWatchActions = ForkWatchActions()
}

/// Mini day-thread card: status, title, question with option buttons, and a link into the thread.
struct ForkWatchCardView: View {
    let card: OpenClawOCard
    @Environment(\.forkWatchActions) private var actions
    @State private var sentOption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: self.card.kind == .work
                ? self.card.kind.statusLabel
                : "\(self.card.agentGlyph) \(self.card.kind.statusLabel)")
                .font(WatchClawType.label(size: 10, weight: .bold))
                .foregroundStyle(self.tint)
                .lineLimit(1)
            Text(verbatim: self.card.title)
                .font(WatchClawType.body(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let body = self.card.bodyText {
                Text(verbatim: body)
                    .font(WatchClawType.body(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(self.card.kind == .question ? 6 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(self.card.pullRequests, id: \.self) { url in
                Text(verbatim: "🔀 \(OpenClawOCard.pullRequestLabel(url))")
                    .font(WatchClawType.label(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            self.options
            if let threadKey = self.card.threadKey {
                Button {
                    self.actions.openThread(threadKey)
                } label: {
                    Label {
                        Text(verbatim: self.card.kind == .question ? "Odpowiedz w wątku" : "Otwórz wątek")
                            .font(WatchClawType.label(size: 11, weight: .semibold))
                    } icon: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityIdentifier("watch-ocard-open-thread")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WatchClawStyle.surface)
        }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(self.tint)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var options: some View {
        if let sentOption {
            Text(verbatim: "✓ Wysłano: \(sentOption)")
                .font(WatchClawType.label(size: 11, weight: .semibold))
                .foregroundStyle(self.tint)
        } else if self.card.kind == .question, let threadKey = self.card.threadKey {
            ForEach(self.card.options, id: \.self) { option in
                Button {
                    self.sentOption = option
                    self.actions.answer(threadKey, option)
                } label: {
                    Text(verbatim: option)
                        .font(WatchClawType.body(size: 12, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(self.tint.opacity(0.85))
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Web card palette: question amber, PR/done green, error red, info purple, progress blue.
    private var tint: Color {
        switch self.card.kind {
        case .question: Color(red: 0.86, green: 0.6, blue: 0.1)
        case .pr, .done: Color(red: 0.2, green: 0.72, blue: 0.36)
        case .error: Color(red: 0.95, green: 0.3, blue: 0.3)
        case .info, .cal: Color(red: 0.62, green: 0.45, blue: 0.95)
        case .start, .night, .work: Color(red: 0.3, green: 0.6, blue: 1.0)
        }
    }
}

/// Shown at the top of an agent thread opened from a card: back to the day thread.
struct ForkWatchDayThreadBackButton: View {
    @Environment(\.forkWatchActions) private var actions

    var body: some View {
        Button {
            self.actions.openThread(nil)
        } label: {
            Label {
                Text(verbatim: "Wątek dnia")
                    .font(WatchClawType.label(size: 11, weight: .bold))
            } icon: {
                Image(systemName: "chevron.left")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(WatchClawStyle.accent)
        .accessibilityIdentifier("watch-day-thread-back")
    }
}
