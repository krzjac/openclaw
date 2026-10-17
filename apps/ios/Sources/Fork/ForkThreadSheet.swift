import Observation
import OpenClawChatUI
import OpenClawKit
import SwiftUI

/// Fork: agent threads open from day-thread cards (and `openclaw://session` links) in a sheet over
/// the day thread, like the web card modal.
@MainActor
@Observable
final class ForkThreadPresenter {
    struct Thread: Identifiable, Equatable {
        let key: String

        var id: String {
            self.key
        }
    }

    static let shared = ForkThreadPresenter()

    var thread: Thread?

    func present(_ threadKey: String) {
        self.thread = Thread(key: threadKey)
    }

    /// `--openclaw-fork-open-thread <key>` presents a thread on launch (simulator screenshots).
    func presentLaunchThreadIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let key = arguments.drop(while: { $0 != "--openclaw-fork-open-thread" }).dropFirst().first,
              key.lowercased().hasPrefix("agent:")
        else { return }
        self.present(key)
    }
}

/// Native chat of one agent thread: cards, history, and a composer that replies in that thread.
struct ForkThreadSheet: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let threadKey: String
    @State private var viewModel: OpenClawChatViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
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
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text(verbatim: "Wątek: \(self.agentID)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.dismiss()
                    } label: {
                        Text(verbatim: "Zamknij")
                            .font(OpenClawType.subheadSemiBold)
                    }
                    .accessibilityIdentifier("ForkThread.Close")
                }
            }
        }
        .task(id: self.threadKey) {
            self.viewModel?.detachTransport()
            let viewModel = OpenClawChatViewModel(
                sessionKey: self.threadKey,
                transport: self.appModel.makeChatTransport(),
                activeAgentId: OpenClawDayThread.agentID(of: self.threadKey)?.lowercased())
            viewModel.load()
            self.viewModel = viewModel
        }
        .onDisappear {
            self.viewModel?.detachTransport()
        }
    }

    private var agentID: String {
        OpenClawDayThread.agentID(of: self.threadKey) ?? "agent"
    }
}
