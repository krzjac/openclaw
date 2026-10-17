import OpenClawKit
import SwiftUI

/// Fork: actions behind day-thread card buttons. The host app wires them to the owner's
/// Gateway host API (`/pr-merge/api/*`); without a handler the buttons stay hidden.
public struct OpenClawOCardActions: Sendable {
    public typealias Answer = @MainActor @Sendable (_ threadKey: String, _ text: String) async throws -> Void
    public typealias CloseThread = @MainActor @Sendable (_ threadKey: String) async throws -> Void
    public typealias Merge = @MainActor @Sendable (_ urls: [String]) async throws -> String?
    public typealias OpenThread = @MainActor @Sendable (_ threadKey: String) -> Void

    public var answer: Answer?
    public var closeThread: CloseThread?
    public var merge: Merge?
    public var openThread: OpenThread?

    public init(
        answer: Answer? = nil,
        closeThread: CloseThread? = nil,
        merge: Merge? = nil,
        openThread: OpenThread? = nil)
    {
        self.answer = answer
        self.closeThread = closeThread
        self.merge = merge
        self.openThread = openThread
    }
}

extension EnvironmentValues {
    /// Fork: host app handlers for day-thread card buttons.
    @Entry public var openClawOCardActions = OpenClawOCardActions()
}

/// Native rendering of an `ocard:` message, mirroring the web day-thread card.
struct ChatOCardView: View {
    private enum Outcome: Equatable {
        case answered(String)
        case retried
        case closed
        case merged(String)
    }

    let card: OpenClawOCard
    @Environment(\.openClawOCardActions) private var actions
    @State private var pendingAction: String?
    @State private var outcome: Outcome?
    @State private var errorText: String?
    @State private var isBodyExpanded = false
    @State private var confirmsClose = false
    @State private var mergeCandidate: String?

    var body: some View {
        VStack(alignment: .leading, spacing: self.card.kind.isCompact ? 4 : 8) {
            self.header
            if let bodyText = self.card.bodyText {
                self.bodyView(bodyText)
            }
            ForEach(self.card.pullRequests, id: \.self) { url in
                self.pullRequestRow(url)
            }
            if !self.card.images.isEmpty {
                self.thumbnails
            }
            self.actionRow
            if let outcomeText {
                Label {
                    Text(verbatim: outcomeText)
                        .font(OpenClawChatTypography.body(size: 13, weight: .semibold, relativeTo: .footnote))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(self.tint)
            }
            if let errorText {
                Text(verbatim: errorText)
                    .font(OpenClawChatTypography.caption)
                    .foregroundStyle(OpenClawChatTheme.danger)
            }
            self.meta
        }
        .padding(.vertical, self.card.kind.isCompact ? 7 : 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenClawChatTheme.subtleCard)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(self.tint)
                .frame(width: self.card.kind.isCompact ? 3 : 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.secondary.opacity(0.2)))
        .opacity(self.card.kind.isCompact ? 0.85 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-ocard-\(self.card.kind.rawValue)")
        .confirmationDialog(
            "Usunąć wątek z listy?",
            isPresented: self.$confirmsClose,
            titleVisibility: .visible)
        {
            Button(role: .destructive) {
                self.run("close") { try await self.closeThread() }
            } label: {
                Text("Usuń wątek")
            }
        } message: {
            Text("Wynik zostaje w tej karcie.")
        }
        .confirmationDialog(
                "Zmerdżować PR?",
                isPresented: Binding(
                    get: { self.mergeCandidate != nil },
                    set: { if !$0 { self.mergeCandidate = nil } }),
                titleVisibility: .visible)
        {
            Button(role: .destructive) {
                let url = self.mergeCandidate
                self.mergeCandidate = nil
                if let url {
                    self.run("merge") { try await self.merge(url) }
                }
            } label: {
                Text("Zmerdżuj")
            }
            } message: {
                Text("Merge zwykle oznacza wdrożenie na produkcję.")
            }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(verbatim: self.card.agentGlyph)
                .font(OpenClawChatTypography.body(size: 13, weight: .regular, relativeTo: .caption))
                .frame(width: 22, height: 22)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(verbatim: self.card.title)
                .font(OpenClawChatTypography.body(size: 15, weight: .semibold, relativeTo: .callout))
                .lineLimit(self.card.kind.isCompact ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: self.card.kind.statusLabel)
                .font(OpenClawChatTypography.body(size: 11.5, weight: .bold, relativeTo: .caption))
                .foregroundStyle(self.tint)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(self.tint.opacity(0.14), in: Capsule())
            if let threadKey = self.card.threadKey, let openThread = self.actions.openThread {
                Button {
                    openThread(threadKey)
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(OpenClawChatTypography.body(size: 14, weight: .semibold, relativeTo: .callout))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(self.card.kind == .question ? "Odpowiedz w wątku" : "Otwórz wątek")
            }
        }
    }

    private func bodyView(_ text: String) -> some View {
        let clips = self.card.kind != .question && text.count > 220 && !self.isBodyExpanded
        return Text(verbatim: text)
            .font(OpenClawChatTypography.body(size: 14, weight: .regular, relativeTo: .callout))
            .lineLimit(clips ? 4 : nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if text.count > 220 { self.isBodyExpanded.toggle() }
            }
    }

    private func pullRequestRow(_ url: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .foregroundStyle(.secondary)
            if let destination = URL(string: url) {
                Link(destination: destination) {
                    Text(verbatim: OpenClawOCard.pullRequestLabel(url))
                        .font(OpenClawChatTypography.body(size: 14, weight: .semibold, relativeTo: .callout))
                        .lineLimit(1)
                }
            } else {
                Text(verbatim: url)
                    .font(OpenClawChatTypography.body(size: 14, weight: .semibold, relativeTo: .callout))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if self.card.kind == .question {
                Text("szkic — po odpowiedzi")
                    .font(OpenClawChatTypography.caption)
                    .foregroundStyle(.secondary)
            } else if self.actions.merge != nil, self.outcome == nil {
                Button {
                    self.mergeCandidate = url
                } label: {
                    Text("Zmerdżuj")
                        .font(OpenClawChatTypography.body(size: 13, weight: .semibold, relativeTo: .footnote))
                }
                .buttonStyle(.borderedProminent)
                .tint(OpenClawChatTheme.success)
                .controlSize(.small)
                .disabled(self.pendingAction != nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.secondary.opacity(0.2)))
    }

    private var thumbnails: some View {
        HStack(spacing: 6) {
            ForEach(self.card.images, id: \.self) { url in
                Link(destination: url) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if self.outcome == nil {
            VStack(alignment: .leading, spacing: 6) {
                if self.card.kind == .question, self.actions.answer != nil, self.card.threadKey != nil {
                    ForEach(self.card.options, id: \.self) { option in
                        Button {
                            self.run(option) { try await self.answer(option) }
                        } label: {
                            HStack(spacing: 6) {
                                if self.pendingAction == option {
                                    ProgressView().controlSize(.small)
                                }
                                Text(verbatim: option)
                                    .font(OpenClawChatTypography.body(
                                        size: 14,
                                        weight: .semibold,
                                        relativeTo: .callout))
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(self.tint)
                        .disabled(self.pendingAction != nil)
                    }
                }
                if self.card.kind == .error, self.actions.answer != nil, self.card.threadKey != nil {
                    Button {
                        self.run("retry") { try await self.retry() }
                    } label: {
                        Text("Ponów")
                            .font(OpenClawChatTypography.body(size: 14, weight: .semibold, relativeTo: .callout))
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.pendingAction != nil)
                }
                if self.card.kind == .done, self.card.pullRequests.isEmpty, self.card.threadKey != nil,
                   self.actions.closeThread != nil
                {
                    Button {
                        self.confirmsClose = true
                    } label: {
                        Text("Usuń wątek")
                            .font(OpenClawChatTypography.body(size: 14, weight: .semibold, relativeTo: .callout))
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.pendingAction != nil)
                }
            }
        }
    }

    private var meta: some View {
        let parts = [
            self.card.agent,
            self.card.date?.formatted(date: .omitted, time: .shortened),
        ].compactMap(\.self)
        return Group {
            if !parts.isEmpty {
                Text(verbatim: parts.joined(separator: " · "))
                    .font(OpenClawChatTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outcomeText: String? {
        switch self.outcome {
        case let .answered(text): "Wysłano: \(text)"
        case .retried: "Poproszono o ponowienie"
        case .closed: "Wątek usunięty z listy"
        case let .merged(text): text
        case nil: nil
        }
    }

    private var tint: Color {
        switch self.card.kind {
        case .question: OpenClawChatTheme.warning
        case .pr, .done: OpenClawChatTheme.success
        case .error: OpenClawChatTheme.danger
        case .info, .cal: OpenClawChatTheme.ocardInfo
        case .start, .night: OpenClawChatTheme.ocardProgress
        }
    }

    private func run(_ action: String, _ operation: @escaping @MainActor () async throws -> Void) {
        guard self.pendingAction == nil else { return }
        self.pendingAction = action
        self.errorText = nil
        Task { @MainActor in
            defer { self.pendingAction = nil }
            do {
                try await operation()
            } catch {
                self.errorText = error.localizedDescription
            }
        }
    }

    private func answer(_ option: String) async throws {
        guard let answer = self.actions.answer, let threadKey = self.card.threadKey else { return }
        try await answer(threadKey, option)
        self.outcome = .answered(option)
    }

    private func retry() async throws {
        guard let answer = self.actions.answer, let threadKey = self.card.threadKey else { return }
        try await answer(threadKey, "Spróbuj ponownie od miejsca, w którym przerwałeś.")
        self.outcome = .retried
    }

    private func closeThread() async throws {
        guard let closeThread = self.actions.closeThread, let threadKey = self.card.threadKey else { return }
        try await closeThread(threadKey)
        self.outcome = .closed
    }

    private func merge(_ url: String) async throws {
        guard let merge = self.actions.merge else { return }
        let summary = try await merge([url])
        self.outcome = .merged(summary ?? "Zmerdżowano \(OpenClawOCard.pullRequestLabel(url))")
    }
}
