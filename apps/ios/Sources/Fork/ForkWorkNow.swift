import Observation
import OpenClawKit
import SwiftUI

/// Fork: "Pracuje teraz" — who is working right now, from the same host data as the web bar.
@MainActor
@Observable
final class ForkWorkNowStore {
    static let shared = ForkWorkNowStore()

    private(set) var items: [OpenClawWorkItem] = []
    @ObservationIgnored private var fetchedAt: Date?

    func refresh(appModel: NodeAppModel, maxAge: TimeInterval = 8) async {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge { return }
        self.fetchedAt = Date()
        if appModel.isLocalChatFixtureEnabled {
            self.items = ForkCardFixture.isEnabled ? Self.fixtureItems() : []
            return
        }
        guard let data = try? await ForkGatewayHostAPI.liveDayData(appModel: appModel),
              let items = OpenClawWorkItem.decodeWorking(from: data)
        else { return }
        if items != self.items { self.items = items }
    }

    private static func fixtureItems() -> [OpenClawWorkItem] {
        let now = Date().timeIntervalSince1970
        return [
            OpenClawWorkItem(
                agent: "kodowanie",
                name: "Układ PDF karty pracy (X21)",
                status: "pracuje",
                since: now - 12 * 60,
                step: "build lp-ng",
                url: "https://example.invalid/chat/kodowanie/~key/dashboard/preview-x21"),
            OpenClawWorkItem(
                agent: "lpng-dane",
                name: "Plan kursu na listopad (X22)",
                status: "pracuje",
                since: now - 3 * 60,
                url: "https://example.invalid/chat/lpng-dane/~key/dashboard/preview-x22"),
        ]
    }
}

/// Collapsible bar above the day thread; rows open the agent thread in the sheet.
struct ForkWorkNowBar: View {
    @Environment(NodeAppModel.self) private var appModel
    /// `--openclaw-work-now-expanded` opens the list on launch (simulator screenshots).
    @State private var isExpanded = ProcessInfo.processInfo.arguments.contains("--openclaw-work-now-expanded")
    private var store: ForkWorkNowStore {
        ForkWorkNowStore.shared
    }

    var body: some View {
        let items = self.store.items
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.snappy) { self.isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(verbatim: "Pracuje teraz · \(items.count)")
                                .font(OpenClawType.subheadSemiBold)
                            if !self.isExpanded, let first = items.first {
                                Text(verbatim: [first.agent, first.name].compactMap(\.self).joined(separator: " · "))
                                    .font(OpenClawType.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: self.isExpanded ? "chevron.up" : "chevron.down")
                                .font(OpenClawType.caption2Bold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ForkWorkNow.Toggle")
                    if self.isExpanded {
                        ForEach(items) { item in
                            self.row(item)
                        }
                    }
                }
                .background(.bar)
                .overlay(alignment: .bottom) {
                    Divider()
                }
            }
        }
        .task {
            // Host events refresh this list; the slow loop only covers a missing event stream.
            await self.store.refresh(appModel: self.appModel, maxAge: 0)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !ForkHostEvents.shared.isConnected {
                    await self.store.refresh(appModel: self.appModel, maxAge: 0)
                }
            }
        }
    }

    private func row(_ item: OpenClawWorkItem) -> some View {
        Button {
            if let key = item.threadKey {
                ForkSheetPresenter.shared.present(.thread(key))
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(OpenClawBrand.ok)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: [item.agent, item.name].compactMap(\.self).joined(separator: " · "))
                        .font(OpenClawType.subhead)
                        .lineLimit(2)
                    Text(verbatim: ["pracuje", item.elapsedText(), item.step].compactMap(\.self)
                        .joined(separator: " · "))
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.threadKey != nil {
                    Image(systemName: "chevron.right")
                        .font(OpenClawType.caption2Bold)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.threadKey == nil)
    }
}

extension ForkWorkNowBar {
    /// Only in the day thread (the `asystent` agent), like the web bar; the card fixture shows it too.
    @MainActor
    static func isShown(sessionKey: String, appModel: NodeAppModel) -> Bool {
        if appModel.isLocalChatFixtureEnabled { return ForkCardFixture.isEnabled }
        return OpenClawDayThread.agentID(of: sessionKey)?.lowercased() == OpenClawDayThread.agentID
    }
}
