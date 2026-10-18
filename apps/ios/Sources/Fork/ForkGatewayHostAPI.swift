import Foundation
import OpenClawChatUI
import OpenClawKit

/// Fork: the owner's Gateway host API (`oc-pr-merge-api`), served by Tailscale Serve under
/// `/pr-merge` on the Gateway origin. Tailscale adds the identity header the API requires, so
/// card buttons work only while this device is on the tailnet.
enum ForkGatewayHostAPI {
    struct Failure: LocalizedError {
        let message: String

        var errorDescription: String? {
            self.message
        }
    }

    @MainActor
    static func cardActions(appModel: NodeAppModel) -> OpenClawOCardActions {
        if appModel.isLocalChatFixtureEnabled {
            return self.fixtureCardActions()
        }
        return OpenClawOCardActions(
            answer: { threadKey, text in
                try await self.answer(appModel: appModel, threadKey: threadKey, text: text)
            },
            closeThread: { threadKey in
                _ = try await self.request(appModel: appModel, path: "/pr-merge/api/close", body: ["key": threadKey])
            },
            merge: { urls in
                try await self.merge(appModel: appModel, urls: urls)
            },
            openThread: { threadKey in
                ForkSheetPresenter.shared.present(.thread(threadKey))
            },
            openPullRequest: { url in
                ForkSheetPresenter.shared.present(.pullRequest(url))
            },
            prefetch: { threadKey, pullRequests in
                if let threadKey { ForkThreadPool.shared.prefetch(threadKey, appModel: appModel) }
                ForkPRStore.shared.prefetch(pullRequests, appModel: appModel)
            },
            pullRequestState: { url in
                ForkPRStore.shared.previews[url]?.state
            })
    }

    @MainActor
    static func merge(appModel: NodeAppModel, urls: [String]) async throws -> String {
        let response = try await self.request(appModel: appModel, path: "/pr-merge/api/merge", body: ["urls": urls])
        return self.mergeSummary(response, urls: urls)
    }

    /// PR preview (description, files, commits, diff) from the host `pr-merge show`.
    @MainActor
    static func pullRequestPreview(appModel: NodeAppModel, url: String) async throws -> Data {
        try await self.get(
            appModel: appModel,
            path: "/pr-merge/api/pr",
            queryItems: [URLQueryItem(name: "u", value: url)],
            timeout: 60)
    }

    /// Live day-thread data (the web "Praca teraz" bar source): the host's fresh `live.json` when it
    /// serves `/pr-merge/api/live`, otherwise the panel copy (refreshed every ~10 s in the container).
    @MainActor
    static func liveDayData(appModel: NodeAppModel) async throws -> Data {
        if let data = try? await self.get(appModel: appModel, path: "/pr-merge/api/live", queryItems: [], timeout: 8) {
            return data
        }
        return try await self.get(
            appModel: appModel,
            path: "/agent-panel-live/agent-claude-data.json",
            queryItems: [],
            timeout: 8)
    }

    @MainActor
    static func get(
        appModel: NodeAppModel,
        path: String,
        queryItems: [URLQueryItem],
        timeout: TimeInterval) async throws -> Data
    {
        guard let config = appModel.activeGatewayConnectConfig,
              let url = AuthenticatedControlUI.pageURL(config: config, path: path, queryItems: queryItems)
        else {
            throw Failure(message: "Brak połączenia z Gatewayem.")
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw Failure(message: "Nie udało się: \((payload["error"] as? String) ?? "HTTP \(status)")")
        }
        return data
    }

    /// Sends a card answer to the agent thread (same path as the web card buttons).
    @MainActor
    static func answer(appModel: NodeAppModel, threadKey: String, text: String) async throws {
        if appModel.isLocalChatFixtureEnabled {
            try await Task.sleep(for: .milliseconds(400))
            return
        }
        _ = try await self.request(
            appModel: appModel,
            path: "/pr-merge/api/answer",
            body: ["key": threadKey, "text": text])
    }

    /// Today's day-thread session key, or nil when the host has not started one yet.
    @MainActor
    static func dayThreadKey(appModel: NodeAppModel) async throws -> String? {
        // Short timeout: Watch snapshots wait for this lookup.
        let response = try await self.request(appModel: appModel, path: "/pr-merge/api/dzien", body: nil, timeout: 6)
        let key = (response["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.lowercased().hasPrefix("agent:") == true ? key : nil
    }

    /// Screenshot and demo fixtures have no Gateway host; buttons succeed locally.
    @MainActor
    private static func fixtureCardActions() -> OpenClawOCardActions {
        OpenClawOCardActions(
            answer: { _, _ in try await Task.sleep(for: .milliseconds(400)) },
            closeThread: { _ in try await Task.sleep(for: .milliseconds(400)) },
            merge: { urls in
                try await Task.sleep(for: .milliseconds(400))
                return "Zmerdżowano \(urls.map(OpenClawOCard.pullRequestLabel).joined(separator: ", ")) (podgląd)"
            },
            openThread: { threadKey in
                ForkSheetPresenter.shared.present(.thread(threadKey))
            },
            openPullRequest: { url in
                ForkSheetPresenter.shared.present(.pullRequest(url))
            })
    }

    /// GET when `body` is nil, otherwise a JSON POST.
    @MainActor
    private static func request(
        appModel: NodeAppModel,
        path: String,
        body: [String: Any]?,
        timeout: TimeInterval = 120) async throws -> [String: Any]
    {
        guard let config = appModel.activeGatewayConnectConfig,
              let url = AuthenticatedControlUI.pageURL(config: config, path: path, queryItems: [])
        else {
            throw Failure(message: "Brak połączenia z Gatewayem.")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // The host API rejects POSTs without this header (no plain cross-site forms).
            request.setValue("1", forHTTPHeaderField: "X-PR-Merge")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 403 {
                throw Failure(message: "Przyciski kart działają tylko w sieci Tailscale.")
            }
            let detail = (payload["error"] as? String) ?? "HTTP \(status)"
            throw Failure(message: "Nie udało się: \(detail)")
        }
        return payload
    }

    private static func mergeSummary(_ response: [String: Any], urls: [String]) -> String {
        let items = response["items"] as? [[String: Any]] ?? []
        let failed = items.filter { ($0["ok"] as? Bool) == false }
        if let first = failed.first {
            let detail = (first["message"] as? String) ?? "merge odrzucony"
            return "Nie zmerdżowano: \(detail)"
        }
        return "Zmerdżowano \(urls.map(OpenClawOCard.pullRequestLabel).joined(separator: ", "))"
    }
}

/// Fork: `openclaw://session?key=agent:<agent>:<rest>` opens that agent thread in a sheet. Kept out
/// of the shared deep-link parser so upstream merges stay small.
enum ForkSessionDeepLink {
    static func sessionKey(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "openclaw" || scheme == "openclaw-debug",
              url.host?.lowercased() == "session",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let key = items.first(where: { $0.name == "key" })?.value?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
                  key.lowercased().hasPrefix("agent:")
        else {
            return nil
        }
        return key
    }
}
