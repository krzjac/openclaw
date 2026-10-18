import Foundation
import OpenClawKit
import UserNotifications

/// Fork: APNs pushes sent by the owner's Gateway host (`oc-apns`, next to the ntfy sender) for agent
/// turns and day-thread cards. Payload:
///
///     { "aps": { "alert": {…}, "thread-id": "<session key>", "category": "openclaw.fork.card" },
///       "openclaw.fork": { "sessionKey": "agent:…", "kind": "question|done|error|pr|info", "pr": "https://…" } }
///
/// Tapping opens the agent thread (or the PR) in the sheet; "Odpowiedz" answers in that thread and
/// "Zmerdżuj" merges the PR. The Watch shows the same actions on mirrored notifications.
enum ForkNotifications {
    static let payloadKey = "openclaw.fork"
    static let cardCategory = "openclaw.fork.card"
    static let pullRequestCategory = "openclaw.fork.pr"
    static let replyAction = "openclaw.fork.reply"
    static let mergeAction = "openclaw.fork.merge"
    static let openAction = "openclaw.fork.open"

    struct Payload: Equatable {
        var sessionKey: String?
        var kind: String?
        var pullRequest: String?
    }

    static func payload(from userInfo: [AnyHashable: Any]) -> Payload? {
        guard let raw = userInfo[self.payloadKey] as? [String: Any] else { return nil }
        let key = (raw["sessionKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pr = (raw["pr"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Payload(
            sessionKey: key?.lowercased().hasPrefix("agent:") == true ? key : nil,
            kind: raw["kind"] as? String,
            pullRequest: pr?.lowercased().hasPrefix("https://") == true ? pr : nil)
    }

    static func registerCategories() {
        self.upsert(self.makeCategories(), center: .current())
        // Upstream registers its approval categories with the same get/set pair at launch; re-check once
        // so neither registration can overwrite the other.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            self.upsert(self.makeCategories(), center: .current())
        }
    }

    private static func makeCategories() -> Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(
            identifier: self.replyAction,
            title: "Odpowiedz",
            options: [],
            textInputButtonTitle: "Wyślij",
            textInputPlaceholder: "Odpowiedź do wątku")
        let open = UNNotificationAction(identifier: self.openAction, title: "Otwórz", options: [.foreground])
        let merge = UNNotificationAction(
            identifier: self.mergeAction,
            title: "Zmerdżuj",
            options: [.authenticationRequired, .destructive])
        return [
            UNNotificationCategory(identifier: self.cardCategory, actions: [reply, open], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: self.pullRequestCategory,
                actions: [merge, reply, open],
                intentIdentifiers: []),
        ]
    }

    private static func upsert(_ categories: Set<UNNotificationCategory>, center: UNUserNotificationCenter) {
        center.getNotificationCategories { existing in
            let identifiers = Set(existing.map(\.identifier))
            guard !categories.allSatisfy({ identifiers.contains($0.identifier) }) else { return }
            var updated = existing
            for category in categories {
                updated.update(with: category)
            }
            center.setNotificationCategories(updated)
        }
    }

    /// `--openclaw-fork-push-fixture`: quiet (provisional) authorization without a system prompt, so the
    /// simulator can show `simctl push` samples in screenshots.
    static func prepareFixtureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--openclaw-fork-push-fixture") else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        }
    }

    /// Foreground: no banner for the thread already open in the sheet.
    @MainActor
    static func shouldPresent(_ payload: Payload) -> Bool {
        guard let key = payload.sessionKey else { return true }
        let presenter = ForkSheetPresenter.shared
        let open = ([presenter.root].compactMap(\.self) + presenter.path).contains(.thread(key))
        return !(open && ForkThreadPool.shared.pinned == key)
    }

    /// Tap or action on a fork notification. Replies and merges run without opening the app.
    @MainActor
    static func handle(
        _ payload: Payload,
        actionIdentifier: String,
        textInput: String?,
        appModel: NodeAppModel?) async
    {
        switch actionIdentifier {
        case self.replyAction:
            guard let key = payload.sessionKey,
                  let text = textInput?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
            else { return }
            do {
                guard let appModel else { throw ForkGatewayHostAPI.Failure(message: "Aplikacja nie jest gotowa.") }
                try await ForkGatewayHostAPI.answer(appModel: appModel, threadKey: key, text: text)
            } catch {
                await self.reportFailure("Odpowiedź nie została wysłana", error: error)
            }
        case self.mergeAction:
            guard let url = payload.pullRequest else { return }
            do {
                guard let appModel else { throw ForkGatewayHostAPI.Failure(message: "Aplikacja nie jest gotowa.") }
                let summary = try await ForkGatewayHostAPI.merge(appModel: appModel, urls: [url])
                await self.report(title: "Merge", body: summary)
            } catch {
                await self.reportFailure("Merge się nie udał", error: error)
            }
        default:
            if let key = payload.sessionKey {
                ForkSheetPresenter.shared.present(.thread(key))
            } else if let url = payload.pullRequest {
                ForkSheetPresenter.shared.present(.pullRequest(url))
            }
        }
    }

    private static func reportFailure(_ title: String, error: Error) async {
        await self.report(title: title, body: "\(error.localizedDescription) Otwórz aplikację i spróbuj ponownie.")
    }

    private static func report(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "openclaw.fork.result.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
