import OpenClawChatUI
import OpenClawKit

/// Fork: agent threads warmed while their cards are on screen. Each pooled view model loads its
/// history over the app's live Gateway connection and keeps receiving events, so opening the
/// thread shows it at once (the web modal instead spawns a CLI per request, ~5 s).
@MainActor
final class ForkThreadPool {
    static let shared = ForkThreadPool()

    private static let capacity = 6

    private var models: [String: OpenClawChatViewModel] = [:]
    private var recency: [String] = []
    private var gatewayID: String?
    /// The page the sheet shows right now; never evicted.
    var pinned: String?

    func prefetch(_ threadKey: String, appModel: NodeAppModel) {
        guard appModel.isOperatorGatewayConnected || appModel.isLocalChatFixtureEnabled else { return }
        _ = self.viewModel(for: threadKey, appModel: appModel)
    }

    func viewModel(for threadKey: String, appModel: NodeAppModel) -> OpenClawChatViewModel {
        self.resetIfGatewayChanged(appModel: appModel)
        if let model = self.models[threadKey] {
            self.touch(threadKey)
            return model
        }
        let model = OpenClawChatViewModel(
            sessionKey: threadKey,
            transport: appModel.makeChatTransport(),
            activeAgentId: OpenClawDayThread.agentID(of: threadKey)?.lowercased())
        model.load()
        self.models[threadKey] = model
        self.touch(threadKey)
        self.evictOverflow()
        return model
    }

    /// A thread the host deleted (merged PR, closed task) leaves the pool.
    func discard(_ threadKey: String) {
        self.recency.removeAll { $0 == threadKey }
        self.models.removeValue(forKey: threadKey)?.detachTransport()
    }

    private func touch(_ threadKey: String) {
        self.recency.removeAll { $0 == threadKey }
        self.recency.append(threadKey)
    }

    private func evictOverflow() {
        // A thread open in the sheet stays attached even when scrolling warms newer ones.
        let presenter = ForkSheetPresenter.shared
        var presented = Set(([presenter.root].compactMap(\.self) + presenter.path).compactMap { item -> String? in
            if case let .thread(key) = item { return key }
            return nil
        })
        if let pinned { presented.insert(pinned) }
        var overflow = self.recency.count - Self.capacity
        for key in self.recency where overflow > 0 && !presented.contains(key) {
            self.recency.removeAll { $0 == key }
            self.models.removeValue(forKey: key)?.detachTransport()
            overflow -= 1
        }
    }

    private func resetIfGatewayChanged(appModel: NodeAppModel) {
        let gatewayID = appModel.connectedGatewayID
        guard gatewayID != self.gatewayID else { return }
        self.gatewayID = gatewayID
        for model in self.models.values {
            model.detachTransport()
        }
        self.models.removeAll()
        self.recency.removeAll()
    }
}
