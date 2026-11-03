import SwiftUI

struct SettingsView: View {
    let credentials: any MetadataCredentialStorage
    let configurationChanged: () -> Void
    @State private var token = ""
    @State private var configured = false
    @State private var errorMessage: String?
    @State private var confirmRemoval = false
    @FocusState private var editingToken: Bool

    var body: some View {
        Form {
            Section("Metadata Provider") {
                Text(configured ? "A TMDB credential is saved on this device." : "No device credential saved.")
                    .accessibilityIdentifier("settings.credentialStatus")
                Text("Use your authorized TMDB API Read Access Token. It is stored in this device’s Keychain and is sent only to TMDB for metadata requests. Your personal library needs no credential.")
                SecureField("TMDB read access token", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editingToken)
                    .accessibilityIdentifier("settings.token")
                Button("Save Provider Credential", systemImage: "key") {
                    perform {
                        let value = try TMDBConfiguration(readAccessToken: token)
                        try credentials.save(value.readAccessToken)
                        token = ""; editingToken = false; configured = true
                        configurationChanged()
                    }
                }.buttonStyle(AppActionStyle()).disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.saveCredential")
                if configured {
                    Button("Remove Provider Credential", role: .destructive) { confirmRemoval = true }
                        .accessibilityIdentifier("settings.removeCredential")
                }
                Text("Removing the credential clears TMDB cached metadata while retaining stable references, ratings, reviews, diary and episode progress. Titles can become identifier placeholders. Reopen an already open detail page to use changed credentials. Local Debug Run-scheme credentials override this device setting when present.").font(.footnote)
                if let url = URL(string: "https://www.themoviedb.org/settings/api") {
                    Link("TMDB API account and authorization", destination: url)
                }
            }
            Section("Your Personal Data") {
                NavigationLink { DataBackupView() } label: {
                    Label("Export or Restore Personal Data", systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings.backup")
            }
            Section {
                NavigationLink("About & Credits") { CreditsView() }
            }
        }
        .appFormScreen("Settings")
        .accessibilityIdentifier("screen.settings")
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingToken = false }.accessibilityIdentifier("settings.keyboardDone") } }
        .task { perform { configured = try credentials.read() != nil } }
        .onDisappear { token = "" }
        .confirmationDialog("Remove this device’s provider credential?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove Credential", role: .destructive) {
                perform { try credentials.remove(); configured = false; configurationChanged() }
            }
        }
        .alert("Provider Configuration", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }
}
