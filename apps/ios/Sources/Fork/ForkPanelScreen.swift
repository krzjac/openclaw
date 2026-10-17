import OpenClawKit
import SwiftUI

/// Fork: the owner's full Control UI (agent panel, day-thread cards, "Praca teraz" bar, merge
/// buttons, dictation) in a WebView. The customizations are injected by the Gateway host, so the
/// page loads them as the browser does. Native embed mode stays off: it hides the Control UI
/// navigation that the agent panel attaches to.
struct ForkPanelScreen: View {
    static let path = "/chat"

    @Environment(NodeAppModel.self) private var appModel
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            self.content
                .navigationTitle(Text(verbatim: "Mój panel"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let headerSidebarAction {
                        OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        let config = self.appModel.activeGatewayConnectConfig
        if let config, config.ingressAuthorization == nil,
           let url = AuthenticatedControlUI.pageURL(config: config, path: Self.path, queryItems: [])
        {
            let storedOperatorToken = AuthenticatedControlUI.storedOperatorToken(config: config)
            AuthenticatedControlUIWebView(
                url: url,
                authScript: AuthenticatedControlUI.authUserScript(
                    config: config,
                    pageURL: url,
                    storedOperatorToken: storedOperatorToken),
                tls: config.tls)
                .id(AuthenticatedControlUI.webContentIdentity(
                    config: config,
                    storedOperatorToken: storedOperatorToken))
                .ignoresSafeArea(edges: .bottom)
                .accessibilityIdentifier("ForkPanel.WebView")
        } else {
            ForkPanelPlaceholder(isFixture: self.appModel.isLocalGatewayFixtureEnabled)
        }
    }
}

private struct ForkPanelPlaceholder: View {
    let isFixture: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "rectangle.3.group")
                    .font(OpenClawType.title2SemiBold)
                    .foregroundStyle(OpenClawBrand.accent)
                Text(verbatim: "Mój panel")
                    .font(OpenClawType.title2SemiBold)
                Text(verbatim: self.isFixture
                    ? "Tryb podglądu nie ma Gatewaya. Po sparowaniu tu otworzy się Twój Control UI."
                    : "Połącz aplikację z Gatewayem (kod setup albo QR), żeby otworzyć tu swój Control UI.")
                    .font(OpenClawType.body)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.features, id: \.self) { feature in
                        Label {
                            Text(verbatim: feature)
                                .font(OpenClawType.body)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(OpenClawBrand.accent)
                        }
                    }
                }
                Text(verbatim: "Panel ładuje się z Gatewaya przez Tailscale, więc telefon musi być w tailnecie.")
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("ForkPanel.Placeholder")
    }

    private static let features = [
        "panel agentów i ich wątki",
        "karty wątku dnia z przyciskami",
        "pasek „Praca teraz” i „🗓️ Dziś”",
        "przyciski „Zmerdżuj” przy PR-ach",
        "własne dyktowanie",
    ]
}
