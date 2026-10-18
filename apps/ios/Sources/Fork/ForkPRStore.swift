import CryptoKit
import Foundation
import Observation
import OpenClawKit

/// Fork: PR previews from the Gateway host (`/pr-merge/api/pr`, ~3 s per fetch). Cards prefetch
/// their PRs in the background; previews live in memory and on disk, so the sheet opens at once
/// with the last copy while a fresh one loads.
@MainActor
@Observable
final class ForkPRStore {
    struct Preview: Decodable, Equatable {
        struct File: Decodable, Equatable {
            var path: String
            var add: Int?
            var del: Int?
        }

        struct Commit: Decodable, Equatable {
            var msg: String?
            var oid: String?
        }

        var repo: String?
        var number: Int?
        var title: String?
        var body: String?
        var state: String?
        var draft: Bool?
        var created_at: String?
        var merged_at: String?
        var author: String?
        var url: String?
        var head: String?
        var base: String?
        var additions: Int?
        var deletions: Int?
        var files: [File]?
        var commits: [Commit]?
        var diff: String?
        var diff_cut: Bool?
    }

    static let shared = ForkPRStore()

    private(set) var previews: [String: Preview] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var loading: Set<String> = []
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var active = 0

    private static let maxConcurrent = 2
    private static let prefetchMaxAge: TimeInterval = 10 * 60
    private static let openMaxAge: TimeInterval = 60

    /// Loads the last saved copy into memory (outside view updates).
    private func warmFromDisk(_ url: String) {
        guard self.previews[url] == nil,
              let data = try? Data(contentsOf: Self.diskURL(for: url)),
              let preview = try? JSONDecoder().decode(Preview.self, from: data)
        else { return }
        self.previews[url] = preview
    }

    func prefetch(_ urls: [String], appModel: NodeAppModel) {
        for url in urls {
            self.warmFromDisk(url)
            if self.isStale(url, maxAge: Self.prefetchMaxAge) {
                self.enqueue(url, appModel: appModel)
            }
        }
    }

    /// After a merge: fetch the new state right away.
    func invalidate(_ url: String, appModel: NodeAppModel) {
        self.fetchedAt[url] = nil
        self.enqueue(url, appModel: appModel, front: true)
    }

    /// Called when the sheet opens: show what we have, refresh if it is older than a minute.
    func refreshForDisplay(_ url: String, appModel: NodeAppModel) {
        self.warmFromDisk(url)
        if self.isStale(url, maxAge: Self.openMaxAge) {
            self.enqueue(url, appModel: appModel, front: true)
        }
    }

    private func isStale(_ url: String, maxAge: TimeInterval) -> Bool {
        guard let fetchedAt = self.fetchedAt[url] else { return true }
        return Date().timeIntervalSince(fetchedAt) > maxAge
    }

    private func enqueue(_ url: String, appModel: NodeAppModel, front: Bool = false) {
        guard !self.loading.contains(url), !self.queue.contains(url) else { return }
        if front { self.queue.insert(url, at: 0) } else { self.queue.append(url) }
        self.pump(appModel: appModel)
    }

    private func pump(appModel: NodeAppModel) {
        while self.active < Self.maxConcurrent, !self.queue.isEmpty {
            let url = self.queue.removeFirst()
            self.active += 1
            self.loading.insert(url)
            Task { @MainActor in
                await self.load(url, appModel: appModel)
                self.loading.remove(url)
                self.active -= 1
                self.pump(appModel: appModel)
            }
        }
    }

    private func load(_ url: String, appModel: NodeAppModel) async {
        if appModel.isLocalChatFixtureEnabled {
            self.previews[url] = Self.fixturePreview(url)
            self.fetchedAt[url] = Date()
            return
        }
        do {
            let data = try await ForkGatewayHostAPI.pullRequestPreview(appModel: appModel, url: url)
            let preview = try JSONDecoder().decode(Preview.self, from: data)
            self.previews[url] = preview
            self.errors[url] = nil
            self.fetchedAt[url] = Date()
            try? FileManager.default.createDirectory(
                at: Self.diskURL(for: url).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? data.write(to: Self.diskURL(for: url), options: .atomic)
        } catch {
            self.errors[url] = error.localizedDescription
        }
    }

    private static func diskURL(for url: String) -> URL {
        let digest = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fork-pr-previews", isDirectory: true)
            .appendingPathComponent("\(digest.prefix(32)).json")
    }

    private static func fixturePreview(_ url: String) -> Preview {
        let label = OpenClawOCard.pullRequestLabel(url)
        return Preview(
            repo: "lp-ng",
            number: Int(label.split(separator: "#").last ?? ""),
            title: "Filtr po grupie i sortowanie na liście uczniów",
            body: "## Co i dlaczego\nDodany filtr po grupie i sortowanie po dacie ostatniej lekcji.\n\n"
                + "## Jak sprawdzono\nBuild zielony, trzy zrzuty (375, 1024, 1366).",
            state: "OPEN",
            draft: false,
            created_at: "2026-10-17T08:12:00Z",
            merged_at: nil,
            author: "krzjac",
            url: url,
            head: "ws/uczniowie-filtr-grupy",
            base: "main",
            additions: 86,
            deletions: 12,
            files: [
                Preview.File(path: "frontend/src/app/students/students-list.component.ts", add: 54, del: 8),
                Preview.File(path: "frontend/src/app/students/students-list.component.html", add: 22, del: 3),
                Preview.File(path: "backend/src/modules/students/students.query.ts", add: 10, del: 1),
            ],
            commits: [Preview.Commit(msg: "Uczniowie: filtr po grupie i sortowanie (X19)", oid: "4f2a9c1e")],
            diff: "diff --git a/backend/src/modules/students/students.query.ts\n"
                + "+  if (query.groupId) filter.groupId = query.groupId\n",
            diff_cut: false)
    }
}
