import SwiftUI

/// GitHub PAT management (§8: 令牌只进 Keychain).
struct GitHubTokenSettingsView: View {
    @State private var tokenText = ""
    @State private var isSet = GitHubTokenStore.hasToken
    @State private var notice: String?
    @State private var noticeIsError = false
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        Section(l10n.t(.githubTokenSection)) {
            LabeledContent(l10n.t(.githubTokenSection)) {
                Text(isSet ? l10n.t(.githubTokenSet) : l10n.t(.githubTokenNotSet))
                    .foregroundStyle(isSet ? .green : .secondary)
            }
            SecureField(l10n.t(.githubTokenPlaceholder), text: $tokenText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button(l10n.t(.githubSaveToken)) { save() }
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                if isSet {
                    Button(l10n.t(.githubDeleteToken), role: .destructive) { remove() }
                }
            }
            Text(l10n.t(.githubTokenDesc))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(noticeIsError ? .red : .green)
            }
        }
    }

    private func save() {
        do {
            try GitHubTokenStore.save(tokenText)
            tokenText = ""
            isSet = true
            notice = l10n.t(.githubTokenSaved)
            noticeIsError = false
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            noticeIsError = true
        }
    }

    private func remove() {
        GitHubTokenStore.delete()
        isSet = false
        notice = l10n.t(.githubTokenDeleted)
        noticeIsError = false
    }
}
