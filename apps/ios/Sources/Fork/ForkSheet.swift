import Observation
import OpenClawChatUI
import OpenClawKit
import SwiftUI

/// Fork: one sheet over the day thread for agent threads and PR previews, like the web card modal.
/// Opening a PR from a thread pushes it inside the same sheet.
enum ForkSheetItem: Hashable, Identifiable {
    case thread(String)
    case pullRequest(String)

    var id: String {
        switch self {
        case let .thread(key): "thread:\(key)"
        case let .pullRequest(url): "pr:\(url)"
        }
    }
}

@MainActor
@Observable
final class ForkSheetPresenter {
    static let shared = ForkSheetPresenter()

    var root: ForkSheetItem?
    var path: [ForkSheetItem] = []

    func present(_ item: ForkSheetItem) {
        guard let root else {
            self.root = item
            self.path = []
            return
        }
        guard root != item, self.path.last != item else { return }
        self.path.append(item)
    }

    func dismiss() {
        self.root = nil
        self.path = []
    }

    /// `--openclaw-fork-open-thread <key>` / `--openclaw-fork-open-pr <url>` (simulator screenshots).
    func presentLaunchItemIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            arguments.drop(while: { $0 != flag }).dropFirst().first
        }
        if let key = value("--openclaw-fork-open-thread"), key.lowercased().hasPrefix("agent:") {
            self.present(.thread(key))
        }
        if let url = value("--openclaw-fork-open-pr"), url.lowercased().hasPrefix("https://") {
            self.present(.pullRequest(url))
        }
    }

    var sheetBinding: Binding<ForkSheetItem?> {
        Binding(
            get: { self.root },
            set: { item in
                if item == nil { self.dismiss() }
            })
    }
}

struct ForkSheetRoot: View {
    let root: ForkSheetItem
    @Bindable private var presenter = ForkSheetPresenter.shared

    var body: some View {
        NavigationStack(path: self.$presenter.path) {
            ForkSheetDestination(item: self.root)
                .navigationDestination(for: ForkSheetItem.self) { item in
                    ForkSheetDestination(item: item)
                }
        }
    }
}

private struct ForkSheetDestination: View {
    let item: ForkSheetItem

    var body: some View {
        Group {
            switch self.item {
            case let .thread(key):
                ForkThreadPager(threadKey: key)
            case let .pullRequest(url):
                ForkPRView(url: url)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ForkSheetPresenter.shared.dismiss()
                } label: {
                    Text(verbatim: "Zamknij")
                        .font(OpenClawType.subheadSemiBold)
                }
                .accessibilityIdentifier("ForkSheet.Close")
            }
        }
    }
}

/// Native chat of one agent thread: cards, history, and a composer that replies in that thread.
/// The view model comes from the prefetch pool, so a warmed thread shows at once.
struct ForkThreadView: View {
    @Environment(NodeAppModel.self) private var appModel
    let threadKey: String

    var body: some View {
        let viewModel = ForkThreadPool.shared.viewModel(for: self.threadKey, appModel: self.appModel)
        OpenClawChatView(
            viewModel: viewModel,
            showsSessionSwitcher: false,
            assistantName: self.agentID,
            assistantAvatarText: String(self.agentID.prefix(1)).uppercased(),
            assistantAvatarTint: OpenClawBrand.accent,
            showsAssistantAvatars: false,
            composerChrome: .clean,
            isComposerEnabled: self.appModel.gatewayConnected,
            messagePlaceholder: "Odpowiedz w wątku…")
            .environment(\.openClawAssistantBubblesInCleanChrome, true)
            .environment(\.openClawOCardActions, ForkGatewayHostAPI.cardActions(appModel: self.appModel))
            .environment(\.openClawOCardThreadIndex, ForkCardIndex.index(for: viewModel.messages))
            .safeAreaInset(edge: .top, spacing: 0) {
                ForkThreadHeader(threadKey: self.threadKey)
            }
            .onAppear {
                viewModel.resumeFromForeground()
            }
    }

    private var agentID: String {
        OpenClawDayThread.agentID(of: self.threadKey) ?? "agent"
    }
}

/// Fork: card thread lookup for a transcript, memoized on the last message so streaming stays cheap.
@MainActor
enum ForkCardIndex {
    private static var memo: [String: OpenClawOCardThreadIndex] = [:]

    static func signature(for messages: [OpenClawChatMessage]) -> String {
        "\(messages.count):\(messages.last?.id.uuidString ?? "")"
    }

    static func index(for messages: [OpenClawChatMessage]) -> OpenClawOCardThreadIndex {
        let signature = self.signature(for: messages)
        if let index = self.memo[signature] { return index }
        let index = OpenClawOCardThreadIndex(cards: self.cards(in: messages))
        if self.memo.count > 16 { self.memo.removeAll() }
        self.memo[signature] = index
        return index
    }

    static func cards(in messages: [OpenClawChatMessage]) -> [OpenClawOCard] {
        messages.compactMap { message -> OpenClawOCard? in
            guard message.role.lowercased() == "assistant" else { return nil }
            let text = message.content.compactMap(\.text).joined(separator: "\n")
            guard OpenClawOCardMarker.containsMarker(text) else { return nil }
            return OpenClawOCardMarker.extract(from: text)?.card
        }
    }
}
