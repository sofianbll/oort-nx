import AppKit
import NXLibraryCore
import ArcanePorting
import SwiftUI

/// Step 1: keep the account, paste a Google client ID, or be guided to create one.
extension CloudSetupAssistant {
    /// Google's own pages, in the order it asks for them.
    static let googleSteps: [(title: String, url: String)] = [
        ("Create a project", "https://console.cloud.google.com/projectcreate"),
        ("Turn on the Google Drive API", "https://console.cloud.google.com/apis/library/drive.googleapis.com"),
        ("Fill in the consent screen. Audience: external", "https://console.cloud.google.com/auth/overview"),
        ("Publish the app, or Google signs you out after 7 days", "https://console.cloud.google.com/auth/audience"),
        ("Create the client. Type: desktop app", "https://console.cloud.google.com/auth/clients/create"),
    ]

    @ViewBuilder var account: some View {
        if waitingForGoogle {
            OortReadout(text: text("Finish in your browser, then come back here."))
            progress("Waiting for Google sign-in in your browser…")
        } else if work?.kind == .inspect { progress("Checking…") }
        else if tool == nil {
            OortReadout(text: text("The connection tool is missing. Choose or download it in Settings → Cloud library → Advanced."))
            pill(.retry, "Try again", action: inspect)
        } else if remotes == nil {
            pill(.retry, "Try again", action: inspect)
        } else {
            switch accountPage {
            case .choose: accountChoice
            case .have: credentials
            case .help: guidedCredentials
            }
        }
    }

    @ViewBuilder private var accountChoice: some View {
        if let existing {
            OortSection(title: text("Your current account")) {
                SeleneOptionRow(icon: .cloudDone, title: accountName(existing.name), about: text("Connected on this Mac"),
                                focused: false, trailing: { EmptyView() })
                    .accessibilityElement(children: .combine)
            }
            OortReadout(text: text("Or use another client ID"))
        } else if bundledClient != nil {
            OortReadout(text: text("Or use another client ID"))
        }
        VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            option(.haveClient, text("I have a client ID"), about: text("Paste the ID and its secret."), icon: .key,
                   action: { openAccountPage(.have) }, trailing: chevron)
            option(.helpCreate, text("Help me create one"), about: text("Five short steps on Google’s site, then paste."), icon: .checklist,
                   action: { openAccountPage(.help) }, trailing: chevron)
        }
    }

    /// The name given to a second account is shown; the usual one says nothing to a player.
    func accountName(_ name: String) -> String { name == "gdrive" ? text("Google Drive") : "\(text("Google Drive")) · \(name)" }

    private func chevron() -> some View {
        MaterialIconView(.chevron, size: SeleneTokens.Space.large).foregroundStyle(SeleneTheme.ink60).accessibilityHidden(true)
    }

    private var guidedCredentials: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                ForEach(Self.googleSteps.indices, id: \.self) { index in
                    option(.link(index), "\(index + 1). \(text(Self.googleSteps[index].title))", action: { openGoogle(index) }) {
                        HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                            Text(text("Open")).seleneFont(.text, .semibold).foregroundStyle(SeleneTheme.glyph)
                            MaterialIconView(.link, size: SeleneTokens.Space.panel).foregroundStyle(SeleneTheme.glyph).accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint(text("Opens in your browser."))
                }
                fields.padding(.top, canvas.u(SeleneTokens.Space.small))
            }
            .padding(canvas.u(SeleneTokens.Space.hairline))
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
            HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
                OortReadout(text: text("On Google’s site it is called a client. Its type is “desktop app”."))
                Spacer(minLength: 0)
                compact(.guide, "Setup guide", action: openGuide)
            }
            fields
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(text("Google ID")).seleneFont(.text, .semibold)
            input(.client) {
                TextField(text("Google ID"), text: $client, prompt: Text(verbatim: "1234-abcd.apps.googleusercontent.com"))
                    .focused($field, equals: .client).onSubmit { field = .secret }
            }
            check(client.isEmpty ? nil : validID, wrong: "Use an ID ending in .apps.googleusercontent.com")
            Text(text("Google secret")).seleneFont(.text, .semibold)
            input(.secret) {
                SecureField(text("Google secret"), text: $secret)
                    .focused($field, equals: .secret).onSubmit(primary)
            }
            check(secret.isEmpty ? nil : validSecret, wrong: "Paste the secret again, without line breaks.")
        }
        .foregroundColor(SeleneTheme.ink)
    }

    @ViewBuilder private func check(_ valid: Bool?, wrong: String) -> some View {
        // The line keeps its place, so the next field does not move while typing.
        SeleneStatusDot(text: text(valid == false ? wrong : "Valid format"),
                        color: valid == false ? SeleneTheme.danger : SeleneTheme.statusOK)
            .opacity(valid == nil ? 0 : 1)
            .accessibilityHidden(valid == nil)
    }

    func openAccountPage(_ page: AccountPage) {
        accountPage = page
        issue = nil
        focus.reset()
        if page == .have { focus.select(.client); field = .client }
        else if page == .help { focus.select(.link(0)) }
    }

    func openGoogle(_ index: Int) {
        guard Self.googleSteps.indices.contains(index), let url = URL(string: Self.googleSteps[index].url) else { return }
        NSWorkspace.shared.open(url)
    }

    func openGuide() { NSWorkspace.shared.open(URL(string: "https://rclone.org/drive/#making-your-own-client-id")!) }

    func inspect() {
        let found = model.resolvedDriveTool
        tool = nil; version = nil; remotes = nil
        model.keepFolders()
        start(.inspect) {
            try Task.checkCancellation()
            guard let found, RcloneStorageBackend.isExecutable(found) else { return }
            tool = found
            let config = RcloneConfiguration(executable: found)
            async let detected = config.version()
            async let listed = config.remotes()
            let (shown, all) = try await (detected, listed)
            try Task.checkCancellation()
            version = shown.replacingOccurrences(of: "rclone ", with: "", options: .anchored)
            remotes = all
            if browsing != nil { browse(browserPath); look() }
        }
    }

    /// Opened for one folder, the list is shown at once; what each folder holds is said as soon as it is known.
    private func look() {
        guard let service, index == nil else { return }
        let remote = draft.remote
        looking?.cancel()
        looking = Task { @MainActor in
            guard let found = try? await service.discoverFolders(kept: nil), !Task.isCancelled, draft.remote == remote else { return }
            index = found.index
            for (folder, path) in [(Folder.library, library?.path), (.sources, sources?.path)] {
                guard let path else { continue }
                if folder == .library { library = choice(.library, path) } else { sources = choice(.sources, path) }
            }
        }
    }

    func connect() {
        guard let tool else { return }
        let id = accountNeedsClient ? client : bundledClient?.id ?? ""
        let password = accountNeedsClient ? secret : bundledClient?.secret ?? ""
        let target = existing?.name
        field = nil; secret = ""; focus.reset()
        model.isChangingConnection = true
        start(.connect) {
            defer { model.isChangingConnection = false }
            if let target {
                let staged = try await CloudDriveCredentialChange.prepare(remote: target, executable: tool,
                                                                          clientID: id, secret: password)
                try Task.checkCancellation()
                replacement = staged
                selectAccount(target)
            } else {
                let remote = try await RcloneConfiguration(executable: tool).connect(clientID: id, secret: password)
                try Task.checkCancellation()
                selectAccount(remote.name)
            }
        }
    }
}
