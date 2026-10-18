import Foundation
import Observation
import OpenClawKit

/// Fork: event-driven refresh from the Gateway host's SSE stream (`/pr-merge/api/events`) — no AI,
/// no fixed polling. Topics: `runs` (agent runs, task registry, deleted threads), `panel` (sessions),
/// and, once the host publishes them, `live` (who is working) and `cards` (new day-thread card).
/// Without a connection it falls back to a slow refresh, like the web cards.
@MainActor
final class ForkHostEvents {
    static let shared = ForkHostEvents()

    private var task: Task<Void, Never>?
    private(set) var isConnected = false

    func start(appModel: NodeAppModel) {
        guard self.task == nil, !appModel.isLocalChatFixtureEnabled else { return }
        self.task = Task { @MainActor [weak appModel] in
            var delay: Duration = .seconds(1)
            while !Task.isCancelled, let appModel {
                await self.refreshAll(appModel: appModel)
                do {
                    try await self.listen(appModel: appModel)
                    delay = .seconds(1)
                } catch {
                    self.isConnected = false
                }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(30))
            }
        }
    }

    func stop() {
        self.task?.cancel()
        self.task = nil
        self.isConnected = false
    }

    private func listen(appModel: NodeAppModel) async throws {
        guard let config = appModel.activeGatewayConnectConfig,
              let url = AuthenticatedControlUI.pageURL(config: config, path: "/pr-merge/api/events", queryItems: [])
        else { throw CancellationError() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CancellationError() }
        self.isConnected = true
        // A missed ping (every 15 s) or silence longer than this means a dead stream.
        let dataTask = bytes.task
        let watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, Date().timeIntervalSince(self.lastLine) > 40 else { continue }
                dataTask.cancel()
                return
            }
        }
        defer { watchdog.cancel() }
        self.lastLine = Date()
        var event = ""
        for try await line in bytes.lines {
            self.lastLine = Date()
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:"), event == "change" {
                let json = Data(line.dropFirst(5).utf8)
                let topics = ((try? JSONSerialization.jsonObject(with: json)) as? [String: Any])?["topics"] as? [String]
                await self.handle(topics: Set(topics ?? []), appModel: appModel)
                event = ""
            }
        }
        self.isConnected = false
    }

    private var lastLine = Date()

    private func handle(topics: Set<String>, appModel: NodeAppModel) async {
        if topics.contains("runs") || topics.contains("live") || topics.contains("panel") {
            await ForkWorkNowStore.shared.refresh(appModel: appModel, maxAge: 0)
        }
        if topics.contains("runs") {
            await ForkRunsStore.shared.refresh(appModel: appModel)
        }
        if !topics.isDisjoint(with: ["runs", "live", "cards"]) {
            await appModel.forkSyncWatchSnapshot(reason: "host_event")
        }
    }

    private func refreshAll(appModel: NodeAppModel) async {
        await ForkWorkNowStore.shared.refresh(appModel: appModel, maxAge: 0)
        await ForkRunsStore.shared.refresh(appModel: appModel)
    }
}

/// Fork: host run state per agent thread — deleted after merge/close, task status, the run's PR.
@MainActor
@Observable
final class ForkRunsStore {
    struct Run: Decodable, Equatable {
        var state: String?
        var pr: String?
        var deleted: Bool?
        var zlecenie: String?
    }

    static let shared = ForkRunsStore()

    private(set) var runs: [String: Run] = [:]
    @ObservationIgnored private var tracked: [String] = []

    func isDeleted(_ threadKey: String) -> Bool {
        self.runs[threadKey]?.deleted == true
    }

    func pullRequest(_ threadKey: String) -> String? {
        self.runs[threadKey]?.pr
    }

    /// Threads the app shows (day-thread cards, open sheet); the host answers up to 40 per request.
    func track(_ keys: [String]) {
        let merged = Array((keys + self.tracked).reduce(into: [String]()) { out, key in
            if !out.contains(key) { out.append(key) }
        }.prefix(40))
        self.tracked = merged
    }

    func refresh(appModel: NodeAppModel) async {
        guard !self.tracked.isEmpty, !appModel.isLocalChatFixtureEnabled else { return }
        let items = self.tracked.map { URLQueryItem(name: "k", value: $0) }
        guard let data = try? await ForkGatewayHostAPI.get(
            appModel: appModel,
            path: "/pr-merge/api/runs",
            queryItems: items,
            timeout: 10),
            let payload = try? JSONDecoder().decode([String: [String: Run]].self, from: data),
            let runs = payload["runs"]
        else { return }
        let newlyDeleted = runs.filter { $0.value.deleted == true && self.runs[$0.key]?.deleted != true }.map(\.key)
        if runs != self.runs { self.runs = runs }
        for key in newlyDeleted {
            ForkThreadPool.shared.discard(key)
        }
    }
}
