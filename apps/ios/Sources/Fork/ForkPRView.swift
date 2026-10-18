import OpenClawKit
import SwiftUI

/// Fork: native PR preview (like the web card modal): status, description, files, commits, diff.
struct ForkPRView: View {
    @Environment(NodeAppModel.self) private var appModel
    let url: String
    @State private var confirmsMerge = false
    @State private var mergeResult: String?
    @State private var isMerging = false

    private var store: ForkPRStore {
        ForkPRStore.shared
    }

    var body: some View {
        let preview = self.store.previews[self.url]
        Group {
            if let preview {
                self.content(preview)
            } else if let error = self.store.errors[self.url] {
                ContentUnavailableView {
                    Label {
                        Text(verbatim: "Nie udało się wczytać PR-a").font(OpenClawType.headline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(verbatim: error).font(OpenClawType.footnote)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: OpenClawOCard.pullRequestLabel(self.url)))
        .onAppear {
            self.store.refreshForDisplay(self.url, appModel: self.appModel)
        }
        .confirmationDialog("Zmerdżować PR?", isPresented: self.$confirmsMerge, titleVisibility: .visible) {
            Button(role: .destructive) {
                self.merge()
            } label: {
                Text(verbatim: "Zmerdżuj")
            }
        } message: {
            Text(verbatim: "Merge zwykle oznacza wdrożenie na produkcję.")
        }
    }

    private func content(_ preview: ForkPRStore.Preview) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(verbatim: self.stateLabel(preview))
                            .font(OpenClawType.caption2Bold)
                            .foregroundStyle(self.stateTint(preview))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(self.stateTint(preview).opacity(0.14), in: Capsule())
                        if self.store.loading.contains(self.url) {
                            ProgressView().controlSize(.mini)
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: "+\(preview.additions ?? 0) −\(preview.deletions ?? 0)")
                            .font(OpenClawType.monoSmall)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: preview.title ?? OpenClawOCard.pullRequestLabel(self.url))
                        .font(OpenClawType.headline)
                    Text(verbatim: self.metaLine(preview))
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                self.actions(preview)
            }
            if let body = preview.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                Section {
                    Text(Self.markdown(body))
                        .font(OpenClawType.callout)
                        .textSelection(.enabled)
                } header: {
                    Text(verbatim: "Opis")
                }
            }
            if let files = preview.files, !files.isEmpty {
                Section {
                    ForEach(files, id: \.path) { file in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: file.path)
                                .font(OpenClawType.monoSmall)
                                .lineLimit(2)
                                .truncationMode(.head)
                            Spacer(minLength: 4)
                            Text(verbatim: "+\(file.add ?? 0) −\(file.del ?? 0)")
                                .font(OpenClawType.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(verbatim: "Pliki · \(files.count)")
                }
            }
            if let commits = preview.commits, !commits.isEmpty {
                Section {
                    ForEach(Array(commits.enumerated()), id: \.offset) { _, commit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: commit.msg ?? "")
                                .font(OpenClawType.subhead)
                            Text(verbatim: commit.oid ?? "")
                                .font(OpenClawType.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(verbatim: "Commity · \(commits.count)")
                }
            }
            if let diff = preview.diff, !diff.isEmpty {
                Section {
                    DisclosureGroup {
                        ScrollView(.horizontal) {
                            Text(verbatim: String(diff.prefix(20000)))
                                .font(OpenClawType.monoSmall)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        if diff.count > 20000 || preview.diff_cut == true {
                            Text(verbatim: "Diff skrócony — całość na GitHubie.")
                                .font(OpenClawType.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(verbatim: "Diff").font(OpenClawType.subheadSemiBold)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func actions(_ preview: ForkPRStore.Preview) -> some View {
        if let mergeResult {
            Text(verbatim: mergeResult)
                .font(OpenClawType.subheadSemiBold)
        } else if preview.state == "OPEN", preview.draft != true {
            Button {
                self.confirmsMerge = true
            } label: {
                HStack {
                    if self.isMerging { ProgressView().controlSize(.small) }
                    Text(verbatim: "Zmerdżuj").font(OpenClawType.subheadSemiBold)
                }
            }
            .disabled(self.isMerging)
        }
        if let destination = URL(string: preview.url ?? self.url) {
            Link(destination: destination) {
                Text(verbatim: "Otwórz na GitHubie").font(OpenClawType.subheadSemiBold)
            }
        }
    }

    private func merge() {
        self.isMerging = true
        Task { @MainActor in
            defer { self.isMerging = false }
            do {
                self.mergeResult = try await ForkGatewayHostAPI.merge(appModel: self.appModel, urls: [self.url])
                self.store.refreshForDisplay(self.url, appModel: self.appModel)
            } catch {
                self.mergeResult = error.localizedDescription
            }
        }
    }

    private func stateLabel(_ preview: ForkPRStore.Preview) -> String {
        if preview.draft == true { return "Szkic" }
        switch preview.state {
        case "MERGED": return "Zmergowany"
        case "CLOSED": return "Zamknięty"
        default: return "Otwarty"
        }
    }

    private func stateTint(_ preview: ForkPRStore.Preview) -> Color {
        if preview.draft == true { return .secondary }
        switch preview.state {
        case "MERGED": return OpenClawBrand.accent
        case "CLOSED": return OpenClawBrand.warn
        default: return OpenClawBrand.ok
        }
    }

    private func metaLine(_ preview: ForkPRStore.Preview) -> String {
        [
            preview.repo.map { "\($0) #\(preview.number.map(String.init) ?? "")" },
            preview.author,
            preview.head.map { "\($0) → \(preview.base ?? "main")" },
        ].compactMap(\.self).joined(separator: " · ")
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
