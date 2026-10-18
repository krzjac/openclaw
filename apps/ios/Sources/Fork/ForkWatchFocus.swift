import Foundation
import Observation
import OpenClawKit

/// Fork: the Watch follows the owner's day thread instead of whatever chat is open on the iPhone.
/// Opening a card's agent thread on the Watch only changes what the Watch shows.
@MainActor
@Observable
final class ForkWatchFocus {
    static let shared = ForkWatchFocus()

    /// Agent thread opened from a card on the Watch; nil shows the day thread.
    var threadOverride: String?
    private(set) var dayThreadKey: String?
    @ObservationIgnored private var dayThreadFetchedAt: Date?
    @ObservationIgnored private var dayThreadTask: Task<String?, Never>?

    private static let dayThreadMaxAge: TimeInterval = 5 * 60

    /// Session the Watch shows and sends to.
    func sessionKey(appModel: NodeAppModel) -> String {
        self.threadOverride ?? self.dayThreadKey ?? appModel.chatSessionKey
    }

    func agentID(for sessionKey: String, appModel: NodeAppModel) -> String? {
        OpenClawDayThread.agentID(of: sessionKey)?.lowercased() ?? appModel.chatDeliveryAgentId
    }

    /// Day thread on the Watch ends with a "Pracuje teraz" card while agents are working.
    func decoratedItems(
        _ items: [OpenClawWatchChatItem],
        sessionKey: String,
        appModel: NodeAppModel) async -> [OpenClawWatchChatItem]
    {
        let isDayThread = appModel.isLocalChatFixtureEnabled
            ? ForkCardFixture.isEnabled
            : OpenClawDayThread.agentID(of: sessionKey)?.lowercased() == OpenClawDayThread.agentID
        guard isDayThread else { return items }
        await ForkWorkNowStore.shared.refresh(appModel: appModel, maxAge: 15)
        guard let card = OpenClawWorkItem.watchCard(for: ForkWorkNowStore.shared.items) else { return items }
        return items + [OpenClawWatchChatItem(
            id: "fork-work-now",
            role: "assistant",
            text: OpenClawOCardMarker.watchText(for: card),
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000))]
    }

    func open(threadKey: String?) {
        let key = threadKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.threadOverride = (key?.isEmpty == false && key != self.dayThreadKey) ? key : nil
    }

    /// Refreshes today's day-thread key from the Gateway host API (`/pr-merge/api/dzien`).
    func refreshDayThreadIfNeeded(appModel: NodeAppModel) async {
        if appModel.isLocalChatFixtureEnabled {
            self.dayThreadKey = nil
            return
        }
        if let fetchedAt = self.dayThreadFetchedAt, Date().timeIntervalSince(fetchedAt) < Self.dayThreadMaxAge {
            return
        }
        if let task = self.dayThreadTask {
            _ = await task.value
            return
        }
        let task = Task { @MainActor in
            try? await ForkGatewayHostAPI.dayThreadKey(appModel: appModel)
        }
        self.dayThreadTask = task
        let key = await task.value
        self.dayThreadTask = nil
        self.dayThreadFetchedAt = Date()
        if let key {
            self.dayThreadKey = key
        }
    }
}
