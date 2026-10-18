import Observation
import OpenClawChatUI
import OpenClawKit
import SwiftUI

/// Fork: agent threads known from the day thread's cards (most recent first) and their PRs.
@MainActor
@Observable
final class ForkThreadDirectory {
    struct Entry: Identifiable, Equatable {
        let key: String
        var title: String
        var pullRequests: [String]
        var updated: Double

        var id: String {
            self.key
        }

        var agent: String {
            OpenClawDayThread.agentID(of: self.key) ?? "agent"
        }
    }

    static let shared = ForkThreadDirectory()

    private(set) var entries: [Entry] = []

    func update(from messages: [OpenClawChatMessage]) {
        let cards = ForkCardIndex.cards(in: messages)
        let index = OpenClawOCardThreadIndex(cards: cards)
        var byKey: [String: Entry] = [:]
        for card in cards {
            guard let key = index.threadKey(for: card) else { continue }
            var entry = byKey[key] ?? Entry(key: key, title: card.title, pullRequests: [], updated: 0)
            if (card.ts ?? 0) >= entry.updated {
                entry.updated = card.ts ?? entry.updated
                if card.kind != .info { entry.title = card.title }
            }
            for url in card.pullRequests where !entry.pullRequests.contains(url) {
                entry.pullRequests.append(url)
            }
            byKey[key] = entry
        }
        let entries = byKey.values.sorted { $0.updated > $1.updated }
        if entries != self.entries { self.entries = entries }
        ForkRunsStore.shared.track(entries.map(\.key))
    }

    func pullRequests(for threadKey: String) -> [String] {
        var urls = self.entries.first { $0.key == threadKey }?.pullRequests ?? []
        if let runPR = ForkRunsStore.shared.pullRequest(threadKey), !urls.contains(runPR) {
            urls.append(runPR)
        }
        return urls
    }

    /// Threads to swipe between: the opened one, who is working now, then recent card threads.
    func pagerKeys(including threadKey: String) -> [String] {
        let working = ForkWorkNowStore.shared.items.compactMap(\.threadKey)
        let recent = self.entries.map(\.key)
        var keys: [String] = []
        for key in [threadKey] + working + recent where !keys.contains(key) {
            keys.append(key)
        }
        return Array(keys.prefix(6))
    }
}

/// Swipe or tap between agent threads inside the sheet; each page is a warmed thread.
struct ForkThreadPager: View {
    @State private var selection: String
    private let openedKey: String

    init(threadKey: String) {
        self.openedKey = threadKey
        self._selection = State(initialValue: threadKey)
    }

    /// Recomputed as the directory and the work list change; the opened thread stays first.
    private var keys: [String] {
        ForkThreadDirectory.shared.pagerKeys(including: self.openedKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            if self.keys.count > 1 {
                self.switcher
            }
            TabView(selection: self.$selection) {
                ForEach(self.keys, id: \.self) { key in
                    ForkThreadView(threadKey: key)
                        .tag(key)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(Text(verbatim: "Wątek: \(OpenClawDayThread.agentID(of: self.selection) ?? "agent")"))
        .onChange(of: self.selection, initial: true) { _, key in
            ForkThreadPool.shared.pinned = key
        }
    }

    private var switcher: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(self.keys, id: \.self) { key in
                        self.chip(key)
                            .id(key)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: self.selection) { _, key in
                withAnimation(.snappy) { proxy.scrollTo(key, anchor: .center) }
            }
        }
        .background(.bar)
    }

    private func chip(_ key: String) -> some View {
        let selected = key == self.selection
        let working = ForkWorkNowStore.shared.items.contains { $0.threadKey == key }
        let deleted = ForkRunsStore.shared.isDeleted(key)
        let title = ForkThreadDirectory.shared.entries.first { $0.key == key }?.title
        return Button {
            withAnimation(.snappy) { self.selection = key }
        } label: {
            HStack(spacing: 5) {
                if working {
                    Circle().fill(OpenClawBrand.ok).frame(width: 6, height: 6)
                }
                Text(verbatim: OpenClawDayThread.agentID(of: key) ?? "agent")
                    .font(OpenClawType.captionSemiBold)
                if let title {
                    Text(verbatim: title)
                        .font(OpenClawType.caption)
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? OpenClawBrand.accent : .primary)
            .background(
                selected ? AnyShapeStyle(OpenClawBrand.accent.opacity(0.14)) : AnyShapeStyle(.quaternary),
                in: Capsule())
            .opacity(deleted ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }
}

/// Top of an agent thread: its PR(s) with merge, and a note when the host already deleted the thread.
struct ForkThreadHeader: View {
    let threadKey: String

    var body: some View {
        let pullRequests = ForkThreadDirectory.shared.pullRequests(for: self.threadKey)
        let deleted = ForkRunsStore.shared.isDeleted(self.threadKey)
        if !pullRequests.isEmpty || deleted {
            VStack(alignment: .leading, spacing: 6) {
                if deleted {
                    Label {
                        Text(verbatim: "Wątek zamknięty — PR zmergowany albo zlecenie zrobione.")
                            .font(OpenClawType.footnote)
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(pullRequests, id: \.self) { url in
                    HStack(spacing: 8) {
                        Button {
                            ForkSheetPresenter.shared.present(.pullRequest(url))
                        } label: {
                            Label {
                                Text(verbatim: OpenClawOCard.pullRequestLabel(url))
                                    .font(OpenClawType.subheadSemiBold)
                            } icon: {
                                Image(systemName: "arrow.triangle.pull")
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 4)
                        ForkMergeButton(url: url, compact: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// Merge with confirmation; shows the PR state instead once it is merged or closed.
struct ForkMergeButton: View {
    @Environment(NodeAppModel.self) private var appModel
    let url: String
    var compact = false
    @State private var confirms = false
    @State private var isMerging = false
    @State private var result: String?

    var body: some View {
        let state = ForkPRStore.shared.previews[self.url]?.state
        Group {
            if let result {
                Text(verbatim: result)
                    .font(OpenClawType.footnoteSemiBold)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if state == "MERGED" {
                Text(verbatim: "Zmergowany")
                    .font(OpenClawType.footnoteSemiBold)
                    .foregroundStyle(OpenClawBrand.accent)
            } else if state == "CLOSED" {
                Text(verbatim: "Zamknięty")
                    .font(OpenClawType.footnoteSemiBold)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    self.confirms = true
                } label: {
                    HStack(spacing: 6) {
                        if self.isMerging { ProgressView().controlSize(.small) }
                        Text(verbatim: "Zmerdżuj")
                            .font(self.compact ? OpenClawType.footnoteSemiBold : OpenClawType.subheadSemiBold)
                    }
                    .frame(maxWidth: self.compact ? nil : .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(OpenClawBrand.ok)
                .controlSize(self.compact ? .small : .large)
                .disabled(self.isMerging)
            }
        }
        .confirmationDialog("Zmerdżować PR?", isPresented: self.$confirms, titleVisibility: .visible) {
            Button(role: .destructive) {
                self.merge()
            } label: {
                Text(verbatim: "Zmerdżuj \(OpenClawOCard.pullRequestLabel(self.url))")
            }
        } message: {
            Text(verbatim: "Merge zwykle oznacza wdrożenie na produkcję. Wątek zlecenia zniknie sam po merge'u.")
        }
        .onAppear {
            ForkPRStore.shared.prefetch([self.url], appModel: self.appModel)
        }
    }

    private func merge() {
        self.isMerging = true
        Task { @MainActor in
            defer { self.isMerging = false }
            do {
                self.result = try await ForkGatewayHostAPI.merge(appModel: self.appModel, urls: [self.url])
                ForkPRStore.shared.invalidate(self.url, appModel: self.appModel)
                await ForkRunsStore.shared.refresh(appModel: self.appModel)
            } catch {
                self.result = error.localizedDescription
            }
        }
    }
}
